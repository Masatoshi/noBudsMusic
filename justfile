set shell := ["bash", "-uc"]
# Optional local overrides, from a gitignored .env. See README.
set dotenv-load := true

bundle_id := "jp.kaizudenki.noBudsMusic"
project := "noBudsMusic.xcodeproj"
scheme := "NoBudsMusic"
config := "Debug"
# Fixed derived-data path so the built .app has a predictable location for
# `just run` and for CI artifact upload.
derived := "build"
app := derived + "/Build/Products/Debug/NoBudsMusic.app"
release_app := derived + "/Build/Products/Release/NoBudsMusic.app"

# Signing identity. Defaults to ad-hoc, which needs no setup but changes on
# every rebuild — and TCC keys the Accessibility / Input Monitoring grants to
# the identity, so an ad-hoc build loses both every time it is rebuilt.
#
# Set these in a gitignored .env to sign with a real identity and keep the
# grants across rebuilds:
#   NOBUDS_CODE_SIGN_IDENTITY=Apple Development
#   NOBUDS_DEVELOPMENT_TEAM=XXXXXXXXXX
sign_identity := env_var_or_default("NOBUDS_CODE_SIGN_IDENTITY", "-")
sign_team := env_var_or_default("NOBUDS_DEVELOPMENT_TEAM", "")

default:
    @just --list

# --- Project ---------------------------------------------------------------

# project.yml is the source of truth; the .xcodeproj is generated and not
# committed. Every recipe below regenerates it first.
#
# Generate noBudsMusic.xcodeproj from project.yml.
generate:
    xcodegen generate

# Show which identity builds are signed with.
signing:
    @echo "identity: {{sign_identity}}"
    @echo "team:     {{sign_team}}"
    @codesign -dv {{app}} 2>&1 | grep -E "Identifier|Authority|TeamIdentifier|Signature" || true

# Regenerate Resources/AppIcon.icns from the SF Symbol the app draws at runtime.
# Committed output; run this after changing the glyph or colour.
icon:
    mkdir -p {{derived}}
    xcrun swift Scripts/make-icon.swift
    iconutil -c icns {{derived}}/AppIcon.iconset -o Resources/AppIcon.icns
    @echo "wrote Resources/AppIcon.icns"

# --- Build / verify --------------------------------------------------------

# Build the app.
build: generate
    xcodebuild -project {{project}} -scheme {{scheme}} -configuration {{config}} \
        -derivedDataPath {{derived}} \
        CODE_SIGN_IDENTITY="{{sign_identity}}" DEVELOPMENT_TEAM="{{sign_team}}" \
        build

# Run the NoBudsMusicCore unit tests.
test: generate
    xcodebuild -project {{project}} -scheme {{scheme}} -configuration {{config}} \
        -derivedDataPath {{derived}} test

# Lint. swift-format ships with the Xcode toolchain; no extra install needed.
lint:
    xcrun swift-format lint --recursive --strict Sources Tests

# Format in place.
fmt:
    xcrun swift-format format --in-place --recursive Sources Tests

# TCC keys the Accessibility and Input Monitoring grants to the bundle id, and
# SMAppService keys the login item to it. A silent mismatch between the copies
# strands both, with no error anywhere.
#
# Check that the bundle id agrees across project.yml, justfile and AppIdentity.
verify-identity:
    #!/usr/bin/env bash
    set -euo pipefail
    swift_id=$(grep -o 'bundleIdentifier = "[^"]*"' Sources/NoBudsMusicCore/AppIdentity.swift | cut -d'"' -f2)
    proj_id=$(grep -o 'PRODUCT_BUNDLE_IDENTIFIER: .*' project.yml | head -1 | awk '{print $2}')
    just_id="{{bundle_id}}"
    echo "AppIdentity.swift: $swift_id"
    echo "project.yml:       $proj_id"
    echo "justfile:          $just_id"
    if [ "$swift_id" != "$proj_id" ] || [ "$swift_id" != "$just_id" ]; then
        echo "bundle identifier mismatch" >&2
        exit 1
    fi

# What CI runs, and the minimum before calling a code change done.
check: verify-identity lint build test

# Remove build products and the generated project.
clean:
    rm -rf {{project}} {{derived}}

# --- Distribution ----------------------------------------------------------

# The Debug bundle carries NoBudsMusic.debug.dylib and __preview.dylib and is
# not portable.
#
# Build a Release .app, which is what should be copied anywhere.
release: generate
    xcodebuild -project {{project}} -scheme {{scheme}} -configuration Release \
        -derivedDataPath {{derived}} \
        CODE_SIGN_IDENTITY="{{sign_identity}}" DEVELOPMENT_TEAM="{{sign_team}}" \
        build
    @echo "built {{release_app}}"

# rsync does not set the com.apple.quarantine attribute, so Gatekeeper will not
# block the app there — which matters because it is signed with a *Development*
# certificate, not Developer ID. The same app downloaded or AirDropped would be
# blocked. Proper distribution needs Developer ID plus notarization; see
# docs/adr/0002-distribution-channel.md.
#
# Copy the Release build to another Mac over ssh, e.g. `just deploy Cherry`.
deploy host: release
    rsync -a --delete {{release_app}} {{host}}:/Applications/
    @echo "copied to {{host}}:/Applications/NoBudsMusic.app"
    @echo "open it there once; it is a menu bar app with no window"

# --- Run -------------------------------------------------------------------

# Ad-hoc signing means the Accessibility and Input Monitoring grants are lost
# on every rebuild -- see `just reset-permissions`.
#
# Build and launch the app.
run: build
    open {{app}}

# Terminate a running instance.
kill:
    -pkill -x NoBudsMusic

# Open the settings window in the running instance without the menu bar item.
settings:
    open "nobudsmusic://settings"

# A rebuild changes the ad-hoc signature, so stale grants must be dropped for
# the prompts to appear again. Scoped to this bundle id only.
#
# Clear this app's Accessibility and Input Monitoring grants.
reset-permissions:
    tccutil reset Accessibility {{bundle_id}}
    tccutil reset ListenEvent {{bundle_id}}

# --- Diagnostics -----------------------------------------------------------

# Live app log: every observed media key and the rule that decided its fate.
logs:
    log stream --predicate 'subsystem == "{{bundle_id}}"' --level debug

# This is the evidence for the bug being fixed.
#
# Live system log: who asked for Play, and whether it caused a launch.
logs-system:
    log stream --predicate 'process == "mediaremoted" OR process == "bluetoothd"' --info

# Snapshot the last 10 minutes into logs/diagnostics.txt for a bug report.
logs-dump:
    mkdir -p logs
    log show --last 10m \
        --predicate 'subsystem == "{{bundle_id}}" OR process == "mediaremoted"' \
        --info > logs/diagnostics.txt
    @echo "wrote logs/diagnostics.txt"

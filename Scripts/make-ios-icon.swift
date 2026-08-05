// Produces the iOS app icon from the note that `just icon` already rendered, so
// the iOS icon, the macOS icon and the Control Center artwork stay the same
// mark.
//
// It exists separately for one reason: iOS icons must be opaque. The macOS
// .icns keeps its transparent background and the system rounds it; an asset
// catalog rejects an icon with an alpha channel, and setting `hasAlpha = false`
// on an NSBitmapImageRep does not remove one — the PNG still carries it.
//
// Flattening is done with CoreGraphics rather than by redrawing through
// AppKit: drawing an SF Symbol into an NSGraphicsContext backed by an
// alpha-less bitmap crashes the Swift interpreter.
//
// Run with `just icon-ios`, which renders the source first. The output is
// committed because the target needs it at build time.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let pixels = 1024
let source = URL(fileURLWithPath: "build/AppIcon.iconset/icon_1024x1024.png")
let out = URL(fileURLWithPath:
    "Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png")

guard
    let src = CGImageSourceCreateWithURL(source as CFURL, nil),
    let note = CGImageSourceCreateImageAtIndex(src, 0, nil)
else { fatalError("run `just icon` first: \(source.path) is missing") }

try FileManager.default.createDirectory(
    at: out.deletingLastPathComponent(), withIntermediateDirectories: true)

// `noneSkipLast` is what makes the result opaque: three colour components and a
// padding byte, with no alpha for the encoder to write out.
guard
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )
else { fatalError("could not allocate an opaque context") }

let bounds = CGRect(x: 0, y: 0, width: pixels, height: pixels)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fill(bounds)
context.draw(note, in: bounds)

guard
    let image = context.makeImage(),
    let dest = CGImageDestinationCreateWithURL(
        out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not encode \(out.path)") }

CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(out.path)")

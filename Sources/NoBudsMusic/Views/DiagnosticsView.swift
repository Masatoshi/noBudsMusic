import NoBudsMusicCore
import SwiftUI

struct DiagnosticsView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let monitorError = model.monitorError {
                monitorErrorBanner(monitorError)
            }
            permissionsSection
            Divider()
            eventsSection
        }
        .onAppear { model.refreshDiagnostics() }
    }

    private var header: some View {
        HStack {
            Text("診断")
                .font(.headline)
            Spacer()
            Toggle(
                "ログを記録",
                isOn: Binding(
                    get: { model.settings.diagnosticsLoggingEnabled },
                    set: { model.setDiagnosticsLoggingEnabled($0) }
                )
            )
            Button("更新") { model.refreshDiagnostics() }
            Button("消去") { model.clearDiagnostics() }
        }
    }

    /// Never fail silently: an empty event list with a dead monitor must not
    /// read as "the headset produced nothing", which is the exact question
    /// Phase 2 is answering.
    private func monitorErrorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("権限")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            permissionRow(
                title: "Input Monitoring",
                detail: "IOHIDManagerで入力を受け取るために必要",
                state: model.permissions.inputMonitoring,
                request: { model.requestInputMonitoring() },
                openSettings: { model.openInputMonitoringSettings() }
            )

            permissionRow(
                title: "Accessibility",
                detail: "CGEventTapでイベントを遮断するために必要",
                state: model.permissions.accessibility,
                request: { model.requestAccessibility() },
                openSettings: { model.openAccessibilitySettings() }
            )

            Label(
                model.isHoldingNowPlaying
                    ? "Now Playing宛先を保持中。Play/Pauseを破棄します。"
                    : "Now Playing宛先を保持していません。Statusをオンにすると保持します。",
                systemImage: model.isHoldingNowPlaying ? "checkmark.circle" : "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Label(
                "HID経路とCGEventTap経路ではイヤホンのタップを捕捉できません"
                    + "（TECH_RESEARCH.md M11）。HID監視は計測器として動作しています。",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        detail: String,
        state: PermissionState,
        request: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol(for: state))
                .foregroundStyle(tint(for: state))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(label(for: state))
                .foregroundStyle(.secondary)
            // Never fail silently: whichever state it is in, there is a way out.
            if state != .granted {
                Button("要求") { request() }
                Button("設定を開く") { openSettings() }
            }
        }
    }

    private func symbol(for state: PermissionState) -> String {
        switch state {
        case .granted: "checkmark.circle.fill"
        case .denied: "xmark.circle.fill"
        case .undetermined: "questionmark.circle"
        }
    }

    private func tint(for state: PermissionState) -> Color {
        switch state {
        case .granted: .green
        case .denied: .red
        case .undetermined: .orange
        }
    }

    private func label(for state: PermissionState) -> String {
        switch state {
        case .granted: "許可済み"
        case .denied: "拒否"
        case .undetermined: "未確定"
        }
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("直近のPlay/Pauseイベント")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if model.recentEvents.isEmpty {
                Text("記録されたイベントはありません。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.recentEvents) {
                    TableColumn("時刻") { entry in
                        Text(entry.timestamp, format: .dateTime.hour().minute().second())
                            .monospacedDigit()
                    }
                    TableColumn("経路") { entry in
                        Text(Self.pathLabel(entry.path))
                    }
                    TableColumn("送信元") { entry in
                        Text(entry.source.displayName)
                    }
                    TableColumn("キー") { entry in
                        Text(String(describing: entry.key))
                    }
                    TableColumn("Usage Page") { entry in
                        Text(entry.usagePage.map(String.init) ?? "-")
                            .monospaced()
                    }
                    TableColumn("Usage") { entry in
                        Text(entry.usage.map(String.init) ?? "-")
                            .monospaced()
                    }
                    TableColumn("遮断") { entry in
                        // The HID path cannot consume an event, so a blocking
                        // outcome there is hypothetical. Saying "した" would be
                        // a lie.
                        if entry.path.canBlock {
                            Text(entry.outcome.isBlocked ? "した" : "しない")
                        } else {
                            Text(entry.outcome.isBlocked ? "観測のみ（判定は遮断）" : "観測のみ")
                                .foregroundStyle(.secondary)
                        }
                    }
                    TableColumn("理由") { entry in
                        Text(Self.explain(entry.outcome.reason))
                    }
                }
            }
        }
    }

    static func pathLabel(_ path: ObservationPath) -> String {
        switch path {
        case .hid: "HID"
        case .eventTap: "EventTap"
        case .nowPlaying: "NowPlaying"
        }
    }

    /// User-facing wording for each rule in `EventFilter`. Kept here rather than
    /// in the core module so the decision logic stays free of UI copy.
    static func explain(_ reason: FilterReason) -> String {
        switch reason {
        case .statusOff: "Statusがオフ"
        case .notPlayPause: "Play/Pause以外のキー"
        case .sourceUnidentified: "送信元を特定できないため通過"
        case .sourceNotBluetooth: "Bluetooth以外のデバイス"
        case .deviceNotConfigured: "未設定のデバイス"
        case .deviceNotBlocked: "このデバイスの遮断はオフ"
        case .deviceBlocked: "遮断対象"
        case .absorbedAsNowPlayingDestination: "Now Playing宛先として破棄"
        }
    }
}

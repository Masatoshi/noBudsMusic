import NoBudsMusicCore
import SwiftUI

struct DiagnosticsView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusSection
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

    // MARK: - Status

    /// Whether the app holds the destination is the only thing that determines
    /// whether it can suppress a launch, and it is not the same as Status being
    /// ON — a real player takes the destination back. Showing the real state
    /// rather than the setting is the difference between a useful diagnostic
    /// and a restatement of the toggle.
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                model.isHoldingNowPlaying
                    ? "Now Playing宛先を保持中。Play/Pauseを破棄します。"
                    : "Now Playing宛先を保持していません。",
                systemImage: model.isHoldingNowPlaying ? "checkmark.circle.fill" : "circle"
            )
            .foregroundStyle(model.isHoldingNowPlaying ? .green : .secondary)

            if model.settings.isEnabled && !model.isHoldingNowPlaying {
                Text(
                    "Statusはオンですが宛先を保持していません。"
                        + "他の再生アプリが宛先を取得している可能性があります。"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Text("このアプリは権限を必要としません。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("直近のコマンド")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if model.recentEvents.isEmpty {
                Text("記録されたコマンドはありません。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.recentEvents) {
                    TableColumn("時刻") { entry in
                        Text(entry.timestamp, format: .dateTime.hour().minute().second())
                            .monospacedDigit()
                    }
                    TableColumn("コマンド") { entry in
                        Text(entry.key.rawValue)
                    }
                    TableColumn("破棄") { entry in
                        Text(entry.outcome.isBlocked ? "した" : "しない")
                    }
                    TableColumn("理由") { entry in
                        Text(Self.explain(entry.outcome.reason))
                    }
                }
            }
        }
    }

    /// User-facing wording for each rule in `EventFilter`. Kept here rather than
    /// in the core module so the decision logic stays free of UI copy.
    static func explain(_ reason: FilterReason) -> String {
        switch reason {
        case .statusOff: "Statusがオフ"
        case .notPlayPause: "Play/Pause以外のコマンドなので転送"
        case .absorbedAsNowPlayingDestination: "Now Playing宛先として破棄"
        }
    }
}

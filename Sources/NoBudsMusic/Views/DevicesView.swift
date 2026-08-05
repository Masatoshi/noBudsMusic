import NoBudsMusicCore
import SwiftUI

struct DevicesView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.devices.isEmpty {
                emptyState
            } else {
                deviceTable
            }
        }
        .onAppear { model.refreshDevices() }
    }

    private var header: some View {
        HStack {
            Text("デバイス")
                .font(.headline)
            Spacer()
            Button("再読み込み") { model.refreshDevices() }
        }
    }

    private var emptyState: some View {
        // An empty list here means IOHIDManager returned nothing, which on a Mac
        // with any input device attached is itself a finding — most likely a
        // missing Input Monitoring grant. Point at Diagnostics rather than
        // letting it read as "no devices".
        VStack(spacing: 6) {
            Text("HIDデバイスが1台も検出されていません。")
            Text("Diagnosticsタブで権限の状態を確認してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deviceTable: some View {
        Table(model.devices) {
            TableColumn("デバイス") { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.rule.displayName)
                    if item.rule.identifier.isCollisionProne {
                        // Required by the brief: collision potential must be
                        // visible, not only logged.
                        Text("同一モデルが複数ある場合は区別できません")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            TableColumn("Transport") { item in
                Text(item.rule.transport.label)
            }

            TableColumn("VID") { item in
                Text(hex(item.info?.vendorID))
                    .monospaced()
            }

            TableColumn("PID") { item in
                Text(hex(item.info?.productID))
                    .monospaced()
            }

            TableColumn("接続") { item in
                Text(item.isConnected ? "接続中" : "未接続")
                    .foregroundStyle(item.isConnected ? .primary : .secondary)
            }

            TableColumn("Block Play/Pause") { item in
                Toggle(
                    "",
                    isOn: Binding(
                        get: { item.rule.blocksPlayPause },
                        set: { model.setBlocking($0, for: item) }
                    )
                )
                .labelsHidden()
                // Only Bluetooth devices are selectable. Others are listed for
                // diagnosis.
                .disabled(!item.isSelectable)
                .help(
                    item.isSelectable
                        ? "このデバイスのPlay/Pauseを遮断します"
                        : "Bluetooth以外のデバイスは遮断対象にできません"
                )
            }
        }
    }

    private func hex(_ value: Int?) -> String {
        guard let value else { return "-" }
        return String(format: "0x%04X", value)
    }
}

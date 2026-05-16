import SwiftUI

/// Aggregate row for the popover. Expands into per-device sub-rows when there
/// are connected devices.
struct BluetoothRow: View {
    @EnvironmentObject var bluetooth: BluetoothService

    var body: some View {
        let s = bluetooth.snapshot
        VStack(alignment: .leading, spacing: 6) {
            StatRow(
                icon: s.isPoweredOn ? "dot.radiowaves.left.and.right" : "wifi.slash",
                tint: s.isPoweredOn ? .primary : .secondary,
                title: "Bluetooth",
                secondary: secondaryLine(for: s),
                trailing: s.isPoweredOn ? "\(s.connectedCount)" : "off"
            )

            if !s.devices.isEmpty {
                VStack(spacing: 5) {
                    ForEach(s.devices) { device in
                        DeviceSubRow(device: device)
                    }
                }
                .padding(.leading, 36)
                .padding(.top, 1)
            }
        }
    }

    private func secondaryLine(for s: BluetoothSnapshot) -> String {
        if !s.isPoweredOn { return "Bluetooth is off" }
        if s.devices.isEmpty { return "No devices connected" }
        if let low = s.lowestBattery { return "Lowest battery: \(low)%" }
        return "\(s.connectedCount) connected"
    }
}

private struct DeviceSubRow: View {
    let device: BTDevice

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: device.kind.systemImage)
                .font(.system(size: 10.5))
                .frame(width: 15)
                .foregroundStyle(.secondary)
            Text(device.name)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if let summary = device.batterySummary {
                Text(summary)
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(tint(for: device.lowestBattery))
            } else {
                Text("—")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.quaternary)
            }
        }
    }

    private func tint(for p: Int?) -> Color {
        guard let p else { return .secondary }
        if p < 20 { return .red }
        if p < 35 { return .yellow }
        return .secondary
    }
}

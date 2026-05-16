import SwiftUI

struct BatteryRow: View {
    @EnvironmentObject var battery: BatteryService
    @AppStorage(AppearancePrefs.popoverIconsKey) private var showIcons = true
    @AppStorage(AppearancePrefs.animValueKey)    private var animateValue = true

    var body: some View {
        let snap = battery.snapshot
        HStack(spacing: 10) {
            if showIcons {
                StatIconBadge(icon: snap.systemImageName, tint: tint(for: snap))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Battery")
                    .font(.system(size: 12.5, weight: .medium))
                Text(snap.secondaryLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            percentText(snap.displayPercent)
        }
        .frame(minHeight: 30)
    }

    @ViewBuilder
    private func percentText(_ value: String) -> some View {
        let t = Text(value)
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .foregroundStyle(.primary)
        if animateValue {
            t.contentTransition(.numericText()).animation(.snappy(duration: 0.3), value: value)
        } else {
            t
        }
    }

    private func tint(for snap: BatterySnapshot) -> Color {
        guard let p = snap.percent else { return .secondary }
        if snap.state == .charging || snap.state == .charged { return .green }
        if p < 20 { return .red }
        if p < 35 { return .yellow }
        return .primary
    }
}

#Preview {
    BatteryRow()
        .environmentObject(BatteryService())
        .padding()
}

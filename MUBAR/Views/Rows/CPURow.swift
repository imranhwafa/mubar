import SwiftUI

struct CPURow: View {
    @EnvironmentObject var cpu: CPUService

    var body: some View {
        let s = cpu.snapshot
        StatRow(
            icon: "cpu",
            tint: tint(for: s.busyPercent),
            title: "CPU",
            secondary: String(format: "User %.0f%% · Sys %.0f%%", s.userPercent, s.systemPercent),
            trailing: s.displayShort
        )
    }

    private func tint(for p: Double) -> Color {
        if p >= 80 { return .red }
        if p >= 50 { return .yellow }
        return .primary
    }
}

struct MemoryRow: View {
    @EnvironmentObject var memory: MemoryService

    var body: some View {
        let s = memory.snapshot
        StatRow(
            icon: "memorychip",
            tint: s.pressurePercent >= 80 ? .red : (s.pressurePercent >= 60 ? .yellow : .primary),
            title: "Memory",
            secondary: s.displayLong,
            trailing: s.displayShort
        )
    }
}

struct NetworkRow: View {
    @EnvironmentObject var network: NetworkService

    var body: some View {
        let s = network.snapshot
        StatRow(
            icon: "arrow.up.arrow.down",
            tint: .primary,
            title: "Network",
            secondary: "Interface: \(s.primaryInterface)",
            trailing: s.displayShort
        )
    }
}

struct DiskRow: View {
    @EnvironmentObject var disk: DiskService

    var body: some View {
        let s = disk.snapshot
        StatRow(
            icon: "internaldrive",
            tint: .primary,
            title: "Disk",
            secondary: "Block I/O",
            trailing: s.displayShort
        )
    }
}

/// Rounded-square tinted icon badge — the macOS Settings-style row glyph.
struct StatIconBadge: View {
    let icon: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

/// Shared, clean row layout for popover stats.
struct StatRow: View {
    let icon: String
    let tint: Color
    let title: String
    let secondary: String
    let trailing: String

    @AppStorage(AppearancePrefs.popoverIconsKey) private var showIcons = true
    @AppStorage(AppearancePrefs.animValueKey)    private var animateValue = true

    var body: some View {
        HStack(spacing: 10) {
            if showIcons {
                StatIconBadge(icon: icon, tint: tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(secondary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailingText
        }
        .frame(minHeight: 30)
    }

    @ViewBuilder
    private var trailingText: some View {
        let t = Text(trailing)
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .foregroundStyle(.primary)
        if animateValue {
            t.contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: trailing)
        } else {
            t
        }
    }
}

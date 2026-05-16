import SwiftUI

struct PopoverRoot: View {
    @AppStorage("show.popover.battery")   private var showBattery   = true
    @AppStorage("show.popover.cpu")       private var showCPU       = true
    @AppStorage("show.popover.memory")    private var showMemory    = true
    @AppStorage("show.popover.network")   private var showNetwork   = true
    @AppStorage("show.popover.disk")      private var showDisk      = true
    @AppStorage("show.popover.bluetooth") private var showBluetooth = true

    @AppStorage(MaterialMode.storageKey)        private var materialRaw = MaterialMode.auto.rawValue
    @AppStorage(AppearancePrefs.accentKey)      private var accentRaw   = AccentTheme.system.rawValue
    @AppStorage(AppearancePrefs.densityKey)     private var densityRaw  = RowDensity.comfortable.rawValue
    @AppStorage(AppearancePrefs.widthKey)       private var widthRaw    = PopoverWidth.standard.rawValue
    @AppStorage(AppearancePrefs.dividersKey)    private var showDividers = true
    @AppStorage(AppearancePrefs.animOpenKey)    private var animateOpen  = true
    @AppStorage(AppearancePrefs.animRowsKey)    private var animateRows  = true

    @State private var showingSettings = false
    @State private var appeared = false

    private var material: MaterialMode { MaterialMode(rawValue: materialRaw) ?? .auto }
    private var accent:   AccentTheme  { AccentTheme(rawValue: accentRaw)   ?? .graphite }
    private var density:  RowDensity   { RowDensity(rawValue: densityRaw)   ?? .comfortable }
    private var width:    PopoverWidth { PopoverWidth(rawValue: widthRaw)   ?? .standard }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderBar(showingSettings: $showingSettings)
            if showDividers { Divider() }
            VStack(spacing: density.rowSpacing) {
                rows
                if !anyEnabled {
                    Text("All stats hidden — open Settings to enable some.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, density.verticalPadding)
            if showDividers { Divider() }
            FooterBar()
        }
        .frame(width: width.points)
        .background(MaterialBackground(mode: material))
        .tint(accent.color)
        .opacity(animateOpen ? (appeared ? 1 : 0) : 1)
        .scaleEffect(animateOpen ? (appeared ? 1 : 0.97) : 1, anchor: .top)
        .onAppear {
            guard animateOpen else { appeared = true; return }
            withAnimation(.easeOut(duration: 0.18)) { appeared = true }
        }
        .onDisappear { appeared = false }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(isPresented: $showingSettings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mubarOpenSettings)) { _ in
            showingSettings = true
        }
    }

    @ViewBuilder
    private var rows: some View {
        let items: [(Bool, AnyView)] = [
            (showBattery,   AnyView(BatteryRow())),
            (showCPU,       AnyView(CPURow())),
            (showMemory,    AnyView(MemoryRow())),
            (showNetwork,   AnyView(NetworkRow())),
            (showDisk,      AnyView(DiskRow())),
            (showBluetooth, AnyView(BluetoothRow())),
        ]
        ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
            if item.0 {
                item.1
                    .transition(animateRows
                        ? .opacity.combined(with: .move(edge: .top))
                        : .identity)
            }
        }
    }

    private var anyEnabled: Bool {
        showBattery || showCPU || showMemory || showNetwork || showDisk || showBluetooth
    }
}

private struct HeaderBar: View {
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
            Text("MUBAR")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
    }
}

private struct FooterBar: View {
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Quit")
                        .font(.system(size: 11))
                }
                .foregroundStyle(hovering ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
            .onHover { hovering = $0 }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
    }
}

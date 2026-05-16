import SwiftUI

/// Two-pane settings: Quick (5 controls, the daily things) and Advanced
/// (everything else, ~15 more controls). Switch via segmented control.
struct SettingsSheet: View {
    @Binding var isPresented: Bool
    @State private var tab: Tab = .quick

    enum Tab: String, CaseIterable, Identifiable {
        case quick = "Quick", appearance = "Appearance", advanced = "Advanced"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MUBAR Settings").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done") { isPresented = false }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16).padding(.bottom, 8)

            Divider()

            ScrollView {
                Group {
                    switch tab {
                    case .quick:      QuickSettingsView()
                    case .appearance: AppearanceSettingsView()
                    case .advanced:   AdvancedSettingsView()
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 420, height: 540)
    }
}

// MARK: - Quick (5 settings)

private struct QuickSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(
                title: "Show in Menu Bar",
                subtitle: "Visible at a glance — toggle each stat on or off."
            ) {
                BarStatsMultiSelect()
            }

            SettingsSection(
                title: "Refresh Rate",
                subtitle: "How often stats update. Realtime uses more battery."
            ) {
                RefreshPresetPicker()
            }

            SettingsSection(
                title: "Popover Material",
                subtitle: "Background style of the popover panel."
            ) {
                MaterialPicker()
            }

            SettingsSection(title: "Bluetooth", subtitle: nil) {
                BluetoothScanningToggle()
                FeatureToggle(key: FeaturePrefs.bluetoothConnectedOnlyKey,
                              label: "Show connected devices only")
                PriorityDevicePicker()
            }

            SettingsSection(title: "Startup", subtitle: nil) {
                LaunchAtLoginToggle()
            }
        }
    }
}

// MARK: - Advanced (~15 settings)

private struct AdvancedSettingsView: View {
    @AppStorage(IntervalPrefs.presetKey) private var presetRaw = RefreshPreset.standard.rawValue

    private var preset: RefreshPreset {
        RefreshPreset(rawValue: presetRaw) ?? .standard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(
                title: "Show in Popover",
                subtitle: "Detailed rows shown when you click the menu bar icon."
            ) {
                ForEach(StatKind.allCases) { kind in
                    KindToggleRow(kind: kind, defaultsKey: StatPrefs.popoverKey(kind))
                }
            }

            SettingsSection(
                title: "Custom Update Intervals",
                subtitle: preset == .custom
                    ? "Per-stat refresh rates (1–120 seconds)."
                    : "Switch Refresh Rate to Custom in Quick Settings to edit these."
            ) {
                ForEach(StatKind.allCases) { kind in
                    IntervalSlider(kind: kind, enabled: preset == .custom)
                }
            }

            SettingsSection(title: "Behavior", subtitle: nil) {
                FeatureToggle(key: FeaturePrefs.hoverToOpenKey,
                              label: "Open popover on hover")
                FeatureToggle(key: FeaturePrefs.batteryShowTimeKey,
                              label: "Battery: show time remaining when on battery")
                FeatureToggle(key: FeaturePrefs.lowBatteryAlertKey,
                              label: "Tint low-battery devices red in popover")
            }

            SettingsSection(title: "Reset", subtitle: nil) {
                Button("Reset all settings to defaults") {
                    resetAll()
                }
                .controlSize(.small)
            }
        }
    }

    private func resetAll() {
        let prefs = UserDefaults.standard
        let keysToWipe: [String] = [
            IntervalPrefs.presetKey,
            FeaturePrefs.bluetoothScanningKey,
            FeaturePrefs.barIconsOnlyKey,
            FeaturePrefs.lowBatteryAlertKey,
            FeaturePrefs.batteryShowTimeKey,
            MaterialMode.storageKey,
            LaunchAtLogin.storageKey,
        ]
        + StatKind.allCases.flatMap {
            [StatPrefs.barKey($0), StatPrefs.popoverKey($0), IntervalPrefs.intervalKey($0)]
        }
        for k in keysToWipe { prefs.removeObject(forKey: k) }
    }
}

// MARK: - Appearance (~17 settings)

private struct AppearanceSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Menu Bar Item", subtitle: "How stats render next to the clock.") {
                LabeledPicker(title: "Display",
                              key: AppearancePrefs.displayModeKey,
                              options: BarDisplayMode.allCases.map { ($0.rawValue, $0.label) },
                              fallback: BarDisplayMode.iconAndValue.rawValue)
                LabeledPicker(title: "Separator",
                              key: AppearancePrefs.separatorKey,
                              options: BarSeparator.allCases.map { ($0.rawValue, $0.label) },
                              fallback: BarSeparator.space.rawValue)
                LabeledPicker(title: "Color",
                              key: AppearancePrefs.colorModeKey,
                              options: BarColorMode.allCases.map { ($0.rawValue, $0.label) },
                              fallback: BarColorMode.colored.rawValue)
                LabeledPicker(title: "Weight",
                              key: AppearancePrefs.textWeightKey,
                              options: BarTextWeight.allCases.map { ($0.rawValue, $0.label) },
                              fallback: BarTextWeight.medium.rawValue)
                LabeledPicker(title: "Spacing",
                              key: AppearancePrefs.spacingKey,
                              options: BarSpacing.allCases.map { ($0.rawValue, $0.label) },
                              fallback: BarSpacing.normal.rawValue)
                DoubleSliderRow(title: "Icon size",
                                key: AppearancePrefs.symbolScaleKey,
                                range: 0.8...1.4, step: 0.05, suffix: "×",
                                fallback: 1.0)
            }

            SettingsSection(title: "Background Pill",
                            subtitle: "An optional rounded background that wraps the stats and grows with them.") {
                PillSettings()
            }

            SettingsSection(title: "Popover", subtitle: "Look of the panel that opens on click.") {
                AccentSwatchPicker()
                LabeledPicker(title: "Density",
                              key: AppearancePrefs.densityKey,
                              options: RowDensity.allCases.map { ($0.rawValue, $0.label) },
                              fallback: RowDensity.comfortable.rawValue)
                LabeledPicker(title: "Width",
                              key: AppearancePrefs.widthKey,
                              options: PopoverWidth.allCases.map { ($0.rawValue, $0.label) },
                              fallback: PopoverWidth.standard.rawValue)
                FeatureToggle(key: AppearancePrefs.dividersKey,    label: "Show section dividers")
                FeatureToggle(key: AppearancePrefs.popoverIconsKey, label: "Show stat icons in rows")
            }

            SettingsSection(title: "Animations", subtitle: "All optional — turn off for a static UI.") {
                FeatureToggle(key: AppearancePrefs.animOpenKey,    label: "Fade & scale popover on open")
                FeatureToggle(key: AppearancePrefs.animValueKey,   label: "Roll numbers when values change")
                FeatureToggle(key: AppearancePrefs.animRowsKey,    label: "Animate rows showing / hiding")
                FeatureToggle(key: AppearancePrefs.animLowBattKey, label: "Flash menu bar on low battery")
                FeatureToggle(key: AppearancePrefs.animBarPulseKey, label: "Pulse menu bar on each update")
            }
        }
    }
}

private struct LabeledPicker: View {
    let title: String
    let key: String
    let options: [(value: String, label: String)]
    let fallback: String
    @State private var selection = ""

    var body: some View {
        HStack {
            Text(title).font(.system(size: 11)).frame(width: 70, alignment: .leading)
            Picker("", selection: $selection) {
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
            .labelsHidden()
            .controlSize(.small)
        }
        .onAppear { selection = UserDefaults.standard.string(forKey: key) ?? fallback }
        .onChange(of: selection) { new in UserDefaults.standard.set(new, forKey: key) }
    }
}

private struct DoubleSliderRow: View {
    let title: String
    let key: String
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    let fallback: Double
    @State private var value: Double = 1

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).frame(width: 70, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text(step >= 1
                 ? String(format: "%.0f%@", value, suffix)
                 : String(format: "%.2f%@", value, suffix))
                .font(.system(size: 11).monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
        .onAppear {
            let v = UserDefaults.standard.double(forKey: key)
            value = v > 0 ? v : fallback
        }
        .onChange(of: value) { new in UserDefaults.standard.set(new, forKey: key) }
    }
}

private struct PillSettings: View {
    @AppStorage(AppearancePrefs.pillEnabledKey) private var enabled = false

    var body: some View {
        FeatureToggle(key: AppearancePrefs.pillEnabledKey, label: "Show background pill")
        if enabled {
            LabeledPicker(title: "Shape",
                          key: AppearancePrefs.pillShapeKey,
                          options: PillShape.allCases.map { ($0.rawValue, $0.label) },
                          fallback: PillShape.capsule.rawValue)
            LabeledPicker(title: "Fill",
                          key: AppearancePrefs.pillFillKey,
                          options: PillFill.allCases.map { ($0.rawValue, $0.label) },
                          fallback: PillFill.subtle.rawValue)
            DoubleSliderRow(title: "Opacity",
                            key: AppearancePrefs.pillOpacityKey,
                            range: 0.05...1.0, step: 0.05, suffix: "",
                            fallback: 0.5)
            DoubleSliderRow(title: "Padding",
                            key: AppearancePrefs.pillPaddingKey,
                            range: 2...16, step: 1, suffix: "pt",
                            fallback: 8)
        }
    }
}

private struct AccentSwatchPicker: View {
    @AppStorage(AppearancePrefs.accentKey) private var raw = AccentTheme.system.rawValue

    var body: some View {
        HStack(spacing: 8) {
            Text("Accent").font(.system(size: 11)).frame(width: 70, alignment: .leading)
            ForEach(AccentTheme.allCases) { theme in
                Circle()
                    .fill(theme.color)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle().strokeBorder(.primary.opacity(raw == theme.rawValue ? 0.9 : 0),
                                              lineWidth: 2)
                    )
                    .overlay(
                        Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5)
                    )
                    .onTapGesture { raw = theme.rawValue }
                    .help(theme.label)
            }
            Spacer()
        }
    }
}

// MARK: - Reusable section + controls

struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold))
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) { content() }
                .padding(.top, 4)
        }
    }
}

private struct BarStatsMultiSelect: View {
    var body: some View {
        ForEach(StatKind.allCases) { kind in
            KindToggleRow(kind: kind, defaultsKey: StatPrefs.barKey(kind))
        }
    }
}

private struct RefreshPresetPicker: View {
    @AppStorage(IntervalPrefs.presetKey) private var raw = RefreshPreset.standard.rawValue

    var body: some View {
        Picker("", selection: $raw) {
            ForEach(RefreshPreset.allCases) { Text($0.label).tag($0.rawValue) }
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
    }
}

private struct MaterialPicker: View {
    @AppStorage(MaterialMode.storageKey) private var raw = MaterialMode.auto.rawValue

    var body: some View {
        Picker("", selection: $raw) {
            ForEach(MaterialMode.allCases) { Text($0.displayName).tag($0.rawValue) }
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
    }
}

private struct BluetoothScanningToggle: View {
    @AppStorage(FeaturePrefs.bluetoothScanningKey) private var on = true

    var body: some View {
        Toggle("Scan for Bluetooth device batteries", isOn: $on)
            .toggleStyle(.switch).controlSize(.small)
        Text("Reads AirPods (Continuity ads) and any device with the standard BLE Battery Service. Disable to free the radio.")
            .font(.system(size: 10)).foregroundStyle(.secondary)
    }
}

private struct PriorityDevicePicker: View {
    @AppStorage(FeaturePrefs.bluetoothPriorityKey) private var selected = ""
    @State private var known: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Priority device")
                    .font(.system(size: 11))
                    .frame(width: 92, alignment: .leading)
                Picker("", selection: $selected) {
                    Text("None — lowest battery").tag("")
                    if !options.isEmpty { Divider() }
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
            }
            Text("When set, the menu bar always shows this device's battery and icon.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .onAppear { known = UserDefaults.standard.stringArray(forKey: FeaturePrefs.bluetoothKnownDevicesKey) ?? [] }
    }

    /// Known devices, guaranteeing the current selection is always listable.
    private var options: [String] {
        var o = known.sorted()
        if !selected.isEmpty && !o.contains(selected) { o.insert(selected, at: 0) }
        return o
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var enabled = LaunchAtLogin.isRegistered

    var body: some View {
        Toggle("Launch MUBAR at login", isOn: $enabled)
            .toggleStyle(.switch).controlSize(.small)
            .onChange(of: enabled) { new in
                if !LaunchAtLogin.setEnabled(new) {
                    enabled = LaunchAtLogin.isRegistered
                }
            }
            .onAppear { enabled = LaunchAtLogin.isRegistered }
    }
}

private struct KindToggleRow: View {
    let kind: StatKind
    let defaultsKey: String
    @State private var value = false

    var body: some View {
        Toggle(isOn: $value) {
            HStack(spacing: 8) {
                Image(systemName: kind.systemImage).frame(width: 18)
                Text(kind.displayName)
            }
        }
        .toggleStyle(.switch).controlSize(.small)
        .onAppear { value = UserDefaults.standard.bool(forKey: defaultsKey) }
        .onChange(of: value) { new in UserDefaults.standard.set(new, forKey: defaultsKey) }
    }
}

private struct FeatureToggle: View {
    let key: String
    let label: String
    @State private var value = false

    var body: some View {
        Toggle(label, isOn: $value)
            .toggleStyle(.switch).controlSize(.small)
            .onAppear { value = UserDefaults.standard.bool(forKey: key) }
            .onChange(of: value) { new in UserDefaults.standard.set(new, forKey: key) }
    }
}

private struct IntervalSlider: View {
    let kind: StatKind
    let enabled: Bool
    @State private var value: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kind.systemImage).frame(width: 18)
            Text(kind.displayName).frame(width: 80, alignment: .leading)
                .font(.system(size: 11))
            Slider(value: $value,
                   in: IntervalPrefs.minInterval...IntervalPrefs.maxInterval,
                   step: 1)
                .disabled(!enabled)
            Text("\(Int(value))s")
                .font(.system(size: 11).monospacedDigit())
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(enabled ? .primary : .secondary)
        }
        .onAppear {
            let v = UserDefaults.standard.double(forKey: IntervalPrefs.intervalKey(kind))
            value = v > 0 ? v : RefreshPreset.standard.defaultInterval(for: kind)
        }
        .onChange(of: value) { new in
            UserDefaults.standard.set(new, forKey: IntervalPrefs.intervalKey(kind))
        }
    }
}

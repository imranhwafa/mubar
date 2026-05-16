import AppKit

/// Builds the NSAttributedString shown in the menu bar status item, honoring
/// every appearance preference (display mode, separator, color mode, text
/// weight, spacing, symbol scale).
enum MenuBarLabelBuilder {

    static func build(
        battery: BatterySnapshot,
        cpu: CPUSnapshot,
        memory: MemorySnapshot,
        network: NetworkSnapshot,
        disk: DiskSnapshot,
        bluetooth: BluetoothSnapshot
    ) -> NSAttributedString {

        let result = NSMutableAttributedString()
        let defaults = UserDefaults.standard
        var first = true

        let mode      = AppearancePrefs.displayMode
        let colorMode = AppearancePrefs.colorMode
        let weight    = AppearancePrefs.textWeight.nsWeight
        let sep       = AppearancePrefs.separator
        let spacing   = AppearancePrefs.spacing
        let scale     = AppearancePrefs.symbolScale

        let textFont = NSFont.menuBarFont(ofSize: 0)
            .withWeight(weight)
            .withMonospacedDigits()
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12 * scale, weight: .medium)

        func textAttrs(_ color: NSColor) -> [NSAttributedString.Key: Any] {
            [.font: textFont, .foregroundColor: color]
        }

        func resolved(_ thresholdColor: NSColor) -> NSColor {
            switch colorMode {
            case .colored:    return thresholdColor
            case .monochrome: return .labelColor
            case .accent:     return AppearancePrefs.accent.nsColor
            }
        }

        func appendSeparator() {
            if !first {
                let s = spacing.separatorPadding + sep.string + spacing.separatorPadding
                result.append(NSAttributedString(string: s, attributes: textAttrs(.labelColor)))
            }
            first = false
        }

        func appendSymbol(_ name: String, color: NSColor) {
            guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig) else { return }
            let tinted = img.tinted(with: color)
            let attach = NSTextAttachment()
            attach.image = tinted
            attach.bounds = CGRect(x: 0, y: -2 * scale, width: tinted.size.width, height: tinted.size.height)
            result.append(NSAttributedString(attachment: attach))
        }

        func appendStat(symbol: String?, value: String, color: NSColor) {
            appendSeparator()
            let c = resolved(color)
            let hasValue = !value.isEmpty
            switch mode {
            case .iconAndValue:
                if let symbol { appendSymbol(symbol, color: c) }
                if hasValue {
                    let prefix = symbol == nil ? "" : " "
                    result.append(NSAttributedString(string: prefix + value, attributes: textAttrs(c)))
                }
            case .iconOnly:
                if let symbol {
                    appendSymbol(symbol, color: c)
                } else if hasValue {
                    result.append(NSAttributedString(string: value, attributes: textAttrs(c)))
                }
            case .valueOnly:
                if hasValue {
                    result.append(NSAttributedString(string: value, attributes: textAttrs(c)))
                } else if let symbol {
                    appendSymbol(symbol, color: c)
                }
            }
        }

        if defaults.bool(forKey: "show.bar.battery") {
            appendStat(symbol: battery.systemImageName,
                       value: battery.displayPercent,
                       color: batteryTint(battery))
        }
        if defaults.bool(forKey: "show.bar.cpu") {
            appendStat(symbol: "cpu", value: cpu.displayShort, color: percentTint(cpu.busyPercent))
        }
        if defaults.bool(forKey: "show.bar.memory") {
            appendStat(symbol: "memorychip", value: memory.displayShort, color: percentTint(memory.pressurePercent))
        }
        if defaults.bool(forKey: "show.bar.network") {
            appendStat(symbol: "arrow.up.arrow.down",
                       value: network.displayShortOrFallback, color: .labelColor)
        }
        if defaults.bool(forKey: "show.bar.disk") {
            appendStat(symbol: "internaldrive", value: disk.displayShort, color: .labelColor)
        }
        if defaults.bool(forKey: "show.bar.bluetooth") {
            appendStat(symbol: bluetoothSymbol(for: bluetooth),
                       value: bluetooth.displayShort, color: bluetoothTint(bluetooth))
        }

        if first {
            appendSymbol("gauge.with.dots.needle.bottom.50percent", color: .labelColor)
        }
        return result
    }

    // MARK: - Pill rendering

    /// Composites the label into an NSImage with a rounded background pill.
    /// The image auto-sizes to the content, so the pill "expands" as stats are
    /// added or values widen. Returned image is non-template (we own its colors).
    static func renderPillImage(
        battery: BatterySnapshot,
        cpu: CPUSnapshot,
        memory: MemorySnapshot,
        network: NetworkSnapshot,
        disk: DiskSnapshot,
        bluetooth: BluetoothSnapshot
    ) -> NSImage {
        let attr = build(battery: battery, cpu: cpu, memory: memory,
                         network: network, disk: disk, bluetooth: bluetooth)
        let textSize = attr.size()
        let barHeight = max(NSStatusBar.system.thickness, 22)
        let hPad = AppearancePrefs.pillPadding
        let width  = ceil(textSize.width) + hPad * 2
        let image  = NSImage(size: NSSize(width: max(width, barHeight), height: barHeight))

        image.lockFocus()

        // Pill background — inset vertically so it doesn't touch the bar edges.
        let vInset: CGFloat = 2.5
        let pillRect = NSRect(x: 0.75, y: vInset,
                              width: image.size.width - 1.5,
                              height: barHeight - vInset * 2)
        let radius = AppearancePrefs.pillShape.radius(forHeight: pillRect.height)
        let path = NSBezierPath(roundedRect: pillRect, xRadius: radius, yRadius: radius)

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let opacity = AppearancePrefs.pillOpacity

        switch AppearancePrefs.pillFill {
        case .subtle:
            let base = isDark ? NSColor.white : NSColor.black
            base.withAlphaComponent(0.14 * opacity).setFill()
            path.fill()
        case .accent:
            AppearancePrefs.accent.nsColor.withAlphaComponent(0.55 * opacity).setFill()
            path.fill()
        case .contrast:
            let base = isDark ? NSColor.white : NSColor.black
            base.withAlphaComponent(0.85 * opacity).setFill()
            path.fill()
        case .outline:
            let base = isDark ? NSColor.white : NSColor.black
            base.withAlphaComponent(0.6 * opacity).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        // Center the text inside the pill.
        let textY = (barHeight - textSize.height) / 2
        attr.draw(at: NSPoint(x: hPad, y: textY))

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Tints

    private static func batteryTint(_ s: BatterySnapshot) -> NSColor {
        if s.state == .charging || s.state == .charged { return .systemGreen }
        guard let p = s.percent else { return .labelColor }
        if p < 20 { return .systemRed }
        if p < 35 { return .systemYellow }
        return .labelColor
    }

    private static func percentTint(_ p: Double) -> NSColor {
        if p >= 80 { return .systemRed }
        if p >= 50 { return .systemYellow }
        return .labelColor
    }

    private static func bluetoothSymbol(for s: BluetoothSnapshot) -> String {
        if !s.isPoweredOn { return "wifi.slash" }
        if let dev = s.priorityDevice { return dev.kind.systemImage }
        return s.devices.first?.kind.systemImage ?? "dot.radiowaves.left.and.right"
    }

    private static func bluetoothTint(_ s: BluetoothSnapshot) -> NSColor {
        // When a priority device is set, tint by that device's battery.
        let level = s.priorityDevice?.lowestBattery ?? s.lowestBattery
        guard let low = level else { return .labelColor }
        if low < 20 { return .systemRed }
        if low < 35 { return .systemYellow }
        return .labelColor
    }
}

// MARK: - NSImage / NSFont helpers

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: size)
        draw(in: rect)
        rect.fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}

private extension NSFont {
    func withMonospacedDigits() -> NSFont {
        let desc = fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
            ]]
        ])
        return NSFont(descriptor: desc, size: 0) ?? self
    }

    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        let desc = fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.weight: weight]
        ])
        return NSFont(descriptor: desc, size: pointSize) ?? self
    }
}

extension NetworkSnapshot {
    var displayShortOrFallback: String {
        let s = displayShort
        return s.isEmpty ? "↓0B ↑0B" : s
    }
}

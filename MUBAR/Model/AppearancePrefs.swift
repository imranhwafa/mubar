import SwiftUI
import AppKit

// MARK: - Menu bar appearance

enum BarDisplayMode: String, CaseIterable, Identifiable {
    case iconAndValue, iconOnly, valueOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .iconAndValue: return "Icon + Value"
        case .iconOnly:     return "Icon Only"
        case .valueOnly:    return "Value Only"
        }
    }
}

enum BarSeparator: String, CaseIterable, Identifiable {
    case space, dot, bullet, bar, slash
    var id: String { rawValue }
    var label: String {
        switch self {
        case .space:  return "Space"
        case .dot:    return "Dot ·"
        case .bullet: return "Bullet •"
        case .bar:    return "Bar |"
        case .slash:  return "Slash /"
        }
    }
    var string: String {
        switch self {
        case .space:  return "  "
        case .dot:    return " · "
        case .bullet: return " • "
        case .bar:    return " | "
        case .slash:  return " / "
        }
    }
}

enum BarColorMode: String, CaseIterable, Identifiable {
    case colored, monochrome, accent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .colored:    return "Colored (thresholds)"
        case .monochrome: return "Monochrome"
        case .accent:     return "Accent tint"
        }
    }
}

enum BarTextWeight: String, CaseIterable, Identifiable {
    case regular, medium, semibold, bold
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var nsWeight: NSFont.Weight {
        switch self {
        case .regular:  return .regular
        case .medium:   return .medium
        case .semibold: return .semibold
        case .bold:     return .bold
        }
    }
}

enum BarSpacing: String, CaseIterable, Identifiable {
    case tight, normal, loose
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// Extra padding multiplier applied to the separator.
    var separatorPadding: String {
        switch self {
        case .tight:  return ""
        case .normal: return " "
        case .loose:  return "   "
        }
    }
}

// MARK: - Menu bar pill background

enum PillShape: String, CaseIterable, Identifiable {
    case capsule, rounded, soft, square
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    func radius(forHeight h: CGFloat) -> CGFloat {
        switch self {
        case .capsule: return h / 2
        case .soft:    return 8
        case .rounded: return 5
        case .square:  return 2
        }
    }
}

enum PillFill: String, CaseIterable, Identifiable {
    case subtle, accent, contrast, outline
    var id: String { rawValue }
    var label: String {
        switch self {
        case .subtle:   return "Subtle"
        case .accent:   return "Accent"
        case .contrast: return "Contrast"
        case .outline:  return "Outline only"
        }
    }
}

// MARK: - Popover appearance

enum AccentTheme: String, CaseIterable, Identifiable {
    case system, blue, purple, green, orange, pink, graphite
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .system:   return .accentColor
        case .blue:     return Color(red: 0.20, green: 0.52, blue: 0.96)
        case .purple:   return Color(red: 0.55, green: 0.35, blue: 0.92)
        case .green:    return Color(red: 0.25, green: 0.72, blue: 0.42)
        case .orange:   return Color(red: 0.96, green: 0.55, blue: 0.18)
        case .pink:     return Color(red: 0.94, green: 0.35, blue: 0.60)
        case .graphite: return Color(red: 0.50, green: 0.52, blue: 0.56)
        }
    }

    var nsColor: NSColor {
        switch self {
        case .system:   return .controlAccentColor
        case .blue:     return NSColor(srgbRed: 0.20, green: 0.52, blue: 0.96, alpha: 1)
        case .purple:   return NSColor(srgbRed: 0.55, green: 0.35, blue: 0.92, alpha: 1)
        case .green:    return NSColor(srgbRed: 0.25, green: 0.72, blue: 0.42, alpha: 1)
        case .orange:   return NSColor(srgbRed: 0.96, green: 0.55, blue: 0.18, alpha: 1)
        case .pink:     return NSColor(srgbRed: 0.94, green: 0.35, blue: 0.60, alpha: 1)
        case .graphite: return NSColor(srgbRed: 0.50, green: 0.52, blue: 0.56, alpha: 1)
        }
    }
}

enum RowDensity: String, CaseIterable, Identifiable {
    case compact, comfortable, spacious
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var rowSpacing: CGFloat {
        switch self {
        case .compact:     return 6
        case .comfortable: return 10
        case .spacious:    return 16
        }
    }
    var verticalPadding: CGFloat {
        switch self {
        case .compact:     return 8
        case .comfortable: return 12
        case .spacious:    return 16
        }
    }
}

enum PopoverWidth: String, CaseIterable, Identifiable {
    case narrow, standard, wide
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var points: CGFloat {
        switch self {
        case .narrow:   return 260
        case .standard: return 300
        case .wide:     return 360
        }
    }
}

// MARK: - Storage

enum AppearancePrefs {
    // Menu bar
    static let displayModeKey = "appearance.bar.displayMode"
    static let separatorKey   = "appearance.bar.separator"
    static let colorModeKey   = "appearance.bar.colorMode"
    static let textWeightKey  = "appearance.bar.textWeight"
    static let spacingKey     = "appearance.bar.spacing"
    static let symbolScaleKey = "appearance.bar.symbolScale"   // Double, 0.8...1.4

    // Menu bar pill background
    static let pillEnabledKey = "appearance.bar.pill.enabled"
    static let pillShapeKey   = "appearance.bar.pill.shape"
    static let pillFillKey    = "appearance.bar.pill.fill"
    static let pillOpacityKey = "appearance.bar.pill.opacity"  // Double, 0.05...1.0
    static let pillPaddingKey = "appearance.bar.pill.padding"  // Double, 2...16

    // Popover
    static let accentKey      = "appearance.popover.accent"
    static let densityKey     = "appearance.popover.density"
    static let widthKey       = "appearance.popover.width"
    static let dividersKey    = "appearance.popover.dividers"
    static let popoverIconsKey = "appearance.popover.icons"

    // Animations
    static let animOpenKey      = "appearance.anim.popoverOpen"
    static let animValueKey     = "appearance.anim.valueRoll"
    static let animRowsKey      = "appearance.anim.rowAppear"
    static let animLowBattKey   = "appearance.anim.lowBatteryFlash"
    static let animBarPulseKey  = "appearance.anim.barUpdatePulse"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            displayModeKey: BarDisplayMode.iconAndValue.rawValue,
            separatorKey:   BarSeparator.space.rawValue,
            colorModeKey:   BarColorMode.colored.rawValue,
            textWeightKey:  BarTextWeight.medium.rawValue,
            spacingKey:     BarSpacing.normal.rawValue,
            symbolScaleKey: 1.0,

            pillEnabledKey: false,
            pillShapeKey:   PillShape.capsule.rawValue,
            pillFillKey:    PillFill.subtle.rawValue,
            pillOpacityKey: 0.5,
            pillPaddingKey: 8.0,

            accentKey:        AccentTheme.graphite.rawValue,
            densityKey:       RowDensity.comfortable.rawValue,
            widthKey:         PopoverWidth.standard.rawValue,
            dividersKey:      true,
            popoverIconsKey:  true,

            animOpenKey:     true,
            animValueKey:    true,
            animRowsKey:     true,
            animLowBattKey:  true,
            animBarPulseKey: false,
        ])
    }

    // Typed accessors
    static var displayMode: BarDisplayMode {
        BarDisplayMode(rawValue: str(displayModeKey)) ?? .iconAndValue
    }
    static var separator: BarSeparator {
        BarSeparator(rawValue: str(separatorKey)) ?? .space
    }
    static var colorMode: BarColorMode {
        BarColorMode(rawValue: str(colorModeKey)) ?? .colored
    }
    static var textWeight: BarTextWeight {
        BarTextWeight(rawValue: str(textWeightKey)) ?? .medium
    }
    static var spacing: BarSpacing {
        BarSpacing(rawValue: str(spacingKey)) ?? .normal
    }
    static var symbolScale: CGFloat {
        let v = UserDefaults.standard.double(forKey: symbolScaleKey)
        return v > 0 ? CGFloat(v) : 1.0
    }
    static var pillEnabled: Bool { bool(pillEnabledKey) }
    static var pillShape: PillShape {
        PillShape(rawValue: str(pillShapeKey)) ?? .capsule
    }
    static var pillFill: PillFill {
        PillFill(rawValue: str(pillFillKey)) ?? .subtle
    }
    static var pillOpacity: CGFloat {
        let v = UserDefaults.standard.double(forKey: pillOpacityKey)
        return v > 0 ? CGFloat(min(max(v, 0.05), 1.0)) : 0.5
    }
    static var pillPadding: CGFloat {
        let v = UserDefaults.standard.double(forKey: pillPaddingKey)
        return v > 0 ? CGFloat(min(max(v, 2), 16)) : 8
    }
    static var accent: AccentTheme {
        AccentTheme(rawValue: str(accentKey)) ?? .graphite
    }
    static var density: RowDensity {
        RowDensity(rawValue: str(densityKey)) ?? .comfortable
    }
    static var width: PopoverWidth {
        PopoverWidth(rawValue: str(widthKey)) ?? .standard
    }
    static var showDividers: Bool   { bool(dividersKey) }
    static var showPopoverIcons: Bool { bool(popoverIconsKey) }
    static var animateOpen: Bool    { bool(animOpenKey) }
    static var animateValue: Bool   { bool(animValueKey) }
    static var animateRows: Bool    { bool(animRowsKey) }
    static var flashLowBattery: Bool { bool(animLowBattKey) }
    static var pulseBarOnUpdate: Bool { bool(animBarPulseKey) }

    private static func str(_ k: String) -> String { UserDefaults.standard.string(forKey: k) ?? "" }
    private static func bool(_ k: String) -> Bool { UserDefaults.standard.bool(forKey: k) }
}

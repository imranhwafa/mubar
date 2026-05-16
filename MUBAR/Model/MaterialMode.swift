import AppKit

enum MaterialMode: String, CaseIterable, Identifiable, Codable {
    case auto, tinted, frosted, solid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:    return "Auto (system)"
        case .tinted:  return "Tinted glass"
        case .frosted: return "Frosted glass"
        case .solid:   return "Solid"
        }
    }

    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .auto:    return .menu
        case .tinted:  return .popover
        case .frosted: return .hudWindow
        case .solid:   return .windowBackground   // unused (solid path takes a different branch)
        }
    }

    var blendingMode: NSVisualEffectView.BlendingMode {
        switch self {
        case .auto, .tinted, .frosted: return .behindWindow
        case .solid: return .withinWindow
        }
    }

    static let storageKey = "popover.material"

    static var current: MaterialMode {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? MaterialMode.auto.rawValue
        return MaterialMode(rawValue: raw) ?? .auto
    }

    static func registerDefault() {
        UserDefaults.standard.register(defaults: [storageKey: MaterialMode.auto.rawValue])
    }
}

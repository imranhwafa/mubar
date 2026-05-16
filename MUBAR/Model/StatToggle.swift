import Foundation

enum StatKind: String, CaseIterable, Identifiable, Codable {
    case battery, cpu, memory, network, disk, bluetooth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .battery:   return "Battery"
        case .cpu:       return "CPU"
        case .memory:    return "Memory"
        case .network:   return "Network"
        case .disk:      return "Disk"
        case .bluetooth: return "Bluetooth"
        }
    }

    var systemImage: String {
        switch self {
        case .battery:   return "battery.100"
        case .cpu:       return "cpu"
        case .memory:    return "memorychip"
        case .network:   return "arrow.up.arrow.down"
        case .disk:      return "internaldrive"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        }
    }
}

/// AppStorage helpers — one bool per stat for the bar, one per stat for the popover.
enum StatPrefs {
    static func barKey(_ k: StatKind)     -> String { "show.bar.\(k.rawValue)" }
    static func popoverKey(_ k: StatKind) -> String { "show.popover.\(k.rawValue)" }

    /// Sensible defaults so the app is useful on first launch without configuration.
    static func registerDefaults() {
        var defaults: [String: Any] = [:]
        for k in StatKind.allCases {
            defaults[barKey(k)] = (k == .battery || k == .cpu)
            defaults[popoverKey(k)] = true
        }
        UserDefaults.standard.register(defaults: defaults)
    }
}

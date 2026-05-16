import Foundation

/// Sampling cadence preset. Controls per-service tick intervals.
/// `custom` reads each interval from UserDefaults independently.
enum RefreshPreset: String, CaseIterable, Identifiable, Codable {
    case realtime, standard, lowPower, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .realtime: return "Realtime (1s, more battery use)"
        case .standard: return "Standard (recommended)"
        case .lowPower: return "Low Power (slower updates)"
        case .custom:   return "Custom"
        }
    }

    func defaultInterval(for k: StatKind) -> TimeInterval {
        switch self {
        case .realtime:
            return 1
        case .standard:
            switch k {
            case .battery:   return 30
            case .cpu:       return 2
            case .memory:    return 5
            case .network:   return 2
            case .disk:      return 5
            case .bluetooth: return 8
            }
        case .lowPower:
            switch k {
            case .battery:   return 60
            case .cpu:       return 5
            case .memory:    return 15
            case .network:   return 5
            case .disk:      return 15
            case .bluetooth: return 20
            }
        case .custom:
            return 0   // unused — caller reads from UserDefaults
        }
    }
}

enum IntervalPrefs {
    static let presetKey = "refresh.preset"
    static func intervalKey(_ k: StatKind) -> String { "interval.\(k.rawValue)" }

    /// Bounds for the custom slider per stat (seconds).
    static let minInterval: TimeInterval = 1
    static let maxInterval: TimeInterval = 120

    static func registerDefaults() {
        var d: [String: Any] = [presetKey: RefreshPreset.standard.rawValue]
        for k in StatKind.allCases {
            d[intervalKey(k)] = RefreshPreset.standard.defaultInterval(for: k)
        }
        UserDefaults.standard.register(defaults: d)
    }

    static var preset: RefreshPreset {
        let raw = UserDefaults.standard.string(forKey: presetKey) ?? RefreshPreset.standard.rawValue
        return RefreshPreset(rawValue: raw) ?? .standard
    }

    /// Effective interval for a stat, honoring preset / custom overrides.
    static func interval(for k: StatKind) -> TimeInterval {
        let p = preset
        if p == .custom {
            let v = UserDefaults.standard.double(forKey: intervalKey(k))
            return v > 0 ? v : RefreshPreset.standard.defaultInterval(for: k)
        }
        return p.defaultInterval(for: k)
    }
}

/// Boolean preferences that don't fit elsewhere.
enum FeaturePrefs {
    static let bluetoothScanningKey      = "feature.bluetooth.scanning"
    static let bluetoothConnectedOnlyKey = "feature.bluetooth.connectedOnly"
    static let bluetoothPriorityKey      = "feature.bluetooth.priorityDevice"   // device name, "" = none
    static let bluetoothKnownDevicesKey  = "feature.bluetooth.knownDevices"     // [String], for the picker
    static let barIconsOnlyKey           = "feature.bar.iconsOnly"
    static let lowBatteryAlertKey        = "feature.lowBatteryAlert"
    static let batteryShowTimeKey        = "feature.battery.showTime"
    static let hoverToOpenKey            = "feature.hoverToOpen"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            bluetoothScanningKey:      true,
            bluetoothConnectedOnlyKey: true,
            barIconsOnlyKey:           false,
            lowBatteryAlertKey:        true,
            batteryShowTimeKey:        true,
            hoverToOpenKey:            true,
        ])
    }
}

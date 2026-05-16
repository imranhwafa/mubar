import Foundation
import IOKit.ps

struct BatterySnapshot: Equatable {
    enum PowerSource: Equatable { case battery, ac, unknown }
    enum ChargeState: Equatable { case charging, discharging, charged, unknown }

    var percent: Int?
    var source: PowerSource = .unknown
    var state: ChargeState = .unknown
    /// Minutes remaining; nil when calculating or unknown.
    var minutesRemaining: Int?
    var isPresent: Bool = false

    static let empty = BatterySnapshot()

    var systemImageName: String {
        guard isPresent, let p = percent else { return "bolt.slash" }
        if state == .charging { return "battery.100.bolt" }
        switch p {
        case ..<10:  return "battery.0"
        case ..<35:  return "battery.25"
        case ..<65:  return "battery.50"
        case ..<90:  return "battery.75"
        default:     return "battery.100"
        }
    }

    var displayPercent: String { percent.map { "\($0)%" } ?? "—" }

    var secondaryLine: String {
        guard isPresent else { return "No battery" }
        switch state {
        case .charged:     return "Fully charged"
        case .charging:
            if let m = minutesRemaining, m > 0 { return "\(formatMinutes(m)) until full" }
            return "Charging"
        case .discharging:
            if let m = minutesRemaining, m > 0 { return "\(formatMinutes(m)) remaining" }
            return "On battery"
        case .unknown:     return source == .ac ? "On power" : "—"
        }
    }

    private func formatMinutes(_ m: Int) -> String {
        let h = m / 60, mm = m % 60
        if h == 0 { return "\(mm)m" }
        if mm == 0 { return "\(h)h" }
        return "\(h)h \(mm)m"
    }
}

@MainActor
final class BatteryService: ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot = .empty

    func tick() {
        snapshot = Self.read()
    }

    private static func read() -> BatterySnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return BatterySnapshot()
        }

        var snap = BatterySnapshot()

        if let providing = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String? {
            switch providing {
            case kIOPSACPowerValue:      snap.source = .ac
            case kIOPSBatteryPowerValue: snap.source = .battery
            default:                     snap.source = .unknown
            }
        }

        for src in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue()
                    as? [String: Any] else { continue }

            if let type = info[kIOPSTypeKey] as? String,
               type != kIOPSInternalBatteryType { continue }

            snap.isPresent = (info[kIOPSIsPresentKey] as? Bool) ?? false

            if let cur = info[kIOPSCurrentCapacityKey] as? Int,
               let max = info[kIOPSMaxCapacityKey] as? Int, max > 0 {
                snap.percent = Int((Double(cur) / Double(max)) * 100.0)
            }

            let isCharging = (info[kIOPSIsChargingKey] as? Bool) ?? false
            let isCharged  = (info[kIOPSIsChargedKey]  as? Bool) ?? false
            if isCharged       { snap.state = .charged }
            else if isCharging { snap.state = .charging }
            else if snap.source == .battery { snap.state = .discharging }
            else                            { snap.state = .unknown }

            let timeKey = isCharging
                ? (info[kIOPSTimeToFullChargeKey] as? Int)
                : (info[kIOPSTimeToEmptyKey] as? Int)
            if let t = timeKey, t > 0 { snap.minutesRemaining = t }

            break
        }

        return snap
    }
}

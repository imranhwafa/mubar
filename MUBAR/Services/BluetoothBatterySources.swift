import Foundation
import IOKit

/// Battery readings keyed by lowercase MAC address (`aa-bb-cc-dd-ee-ff`).
/// Each source returns whatever it knows; `BluetoothService` merges them.
enum BluetoothBatterySources {

    struct Reading {
        var single: Int?
        var left: Int?
        var right: Int?
        var caseLevel: Int?

        var isEmpty: Bool { single == nil && left == nil && right == nil && caseLevel == nil }
    }

    // MARK: - Public

    /// Read every available local source. Cheap enough to call from a
    /// background tick.
    static func collect() -> [String: Reading] {
        var out: [String: Reading] = [:]
        merge(plistDeviceCache(), into: &out)
        merge(ioRegistry(),       into: &out)
        return out
    }

    private static func merge(_ src: [String: Reading], into dst: inout [String: Reading]) {
        for (k, v) in src {
            var existing = dst[k] ?? Reading()
            existing.single    = existing.single    ?? v.single
            existing.left      = existing.left      ?? v.left
            existing.right     = existing.right     ?? v.right
            existing.caseLevel = existing.caseLevel ?? v.caseLevel
            if !existing.isEmpty { dst[k] = existing }
        }
    }

    // MARK: - /Library/Preferences/com.apple.Bluetooth.plist DeviceCache

    /// macOS caches recent battery readings here for AirPods, Magic devices,
    /// many BLE peripherals. Keys vary across versions:
    ///   BatteryPercent / BatteryPercentSingle  → single
    ///   BatteryPercentLeft / BatteryPercentRight / BatteryPercentCase
    static func plistDeviceCache(path: String = "/Library/Preferences/com.apple.Bluetooth.plist") -> [String: Reading] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let any = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let cache = any["DeviceCache"] as? [String: [String: Any]]
        else { return [:] }

        var out: [String: Reading] = [:]
        for (rawAddr, info) in cache {
            let addr = rawAddr.lowercased().replacingOccurrences(of: ":", with: "-")
            var r = Reading()
            r.single    = number(info["BatteryPercent"]) ?? number(info["BatteryPercentSingle"])
            r.left      = number(info["BatteryPercentLeft"])
            r.right     = number(info["BatteryPercentRight"])
            r.caseLevel = number(info["BatteryPercentCase"])
            if !r.isEmpty { out[addr] = r }
        }
        return out
    }

    // MARK: - IORegistry walk

    /// Walks every IOService matching `IOBluetoothDevice` (and HID children)
    /// looking for `BatteryPercent` properties published by drivers. Catches
    /// Magic Mouse/Keyboard, BLE peripherals with the Battery Service, and
    /// some headphones whose drivers expose battery this way.
    static func ioRegistry() -> [String: Reading] {
        var out: [String: Reading] = [:]

        for matchClass in ["IOBluetoothDevice", "AppleDeviceManagementHIDEventService", "IOBluetoothHIDDriver"] {
            var iter: io_iterator_t = 0
            guard let match = IOServiceMatching(matchClass) else { continue }
            guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iter) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iter) }

            while case let svc = IOIteratorNext(iter), svc != 0 {
                defer { IOObjectRelease(svc) }
                var propsRef: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(svc, &propsRef, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) == KERN_SUCCESS,
                      let props = propsRef?.takeRetainedValue() as? [String: Any]
                else { continue }

                guard let address = addressString(from: props) else { continue }

                var r = Reading()
                r.single    = number(props["BatteryPercent"])      ?? number(props["BatteryPercentSingle"])
                r.left      = number(props["BatteryPercentLeft"])
                r.right     = number(props["BatteryPercentRight"])
                r.caseLevel = number(props["BatteryPercentCase"])

                if r.isEmpty { continue }

                let prev = out[address] ?? Reading()
                out[address] = Reading(
                    single:    r.single    ?? prev.single,
                    left:      r.left      ?? prev.left,
                    right:     r.right     ?? prev.right,
                    caseLevel: r.caseLevel ?? prev.caseLevel
                )
            }
        }
        return out
    }

    private static func addressString(from props: [String: Any]) -> String? {
        if let s = props["DeviceAddress"] as? String {
            return s.lowercased().replacingOccurrences(of: ":", with: "-")
        }
        if let data = props["DeviceAddress"] as? Data, data.count == 6 {
            let bytes = data.map { String(format: "%02x", $0) }
            return bytes.joined(separator: "-")
        }
        return nil
    }

    private static func number(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) }
        return nil
    }
}

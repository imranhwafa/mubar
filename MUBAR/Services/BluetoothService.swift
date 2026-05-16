import Foundation
import Combine

struct BTDevice: Identifiable, Equatable {
    enum Kind: Equatable {
        case headphones, earbuds, speaker, mouse, keyboard, controller, phone, watch, other
        var systemImage: String {
            switch self {
            case .headphones: return "headphones"
            case .earbuds:    return "earbuds"
            case .speaker:    return "hifispeaker"
            case .mouse:      return "computermouse"
            case .keyboard:   return "keyboard"
            case .controller: return "gamecontroller"
            case .phone:      return "iphone"
            case .watch:      return "applewatch"
            case .other:      return "dot.radiowaves.left.and.right"
            }
        }
    }

    let id: String
    var name: String
    var kind: Kind
    var isConnected: Bool
    var battery: Int?
    var batteryLeft: Int?
    var batteryRight: Int?
    var batteryCase: Int?

    var lowestBattery: Int? {
        [battery, batteryLeft, batteryRight, batteryCase].compactMap { $0 }.min()
    }

    var batterySummary: String? {
        if let l = batteryLeft, let r = batteryRight {
            if let c = batteryCase { return "L \(l)% · R \(r)% · Case \(c)%" }
            return "L \(l)% · R \(r)%"
        }
        if let b = battery { return "\(b)%" }
        return nil
    }
}

struct BluetoothSnapshot: Equatable {
    var isPoweredOn: Bool = false
    var devices: [BTDevice] = []
    var hasFreshData: Bool = false

    /// User-chosen priority device (by name). When set and connected, the menu
    /// bar shows this device's battery instead of the count·lowest aggregate.
    var preferredDeviceName: String = ""

    var connectedCount: Int { devices.count }

    var lowestBattery: Int? {
        devices.compactMap(\.lowestBattery).min()
    }

    /// The priority device if one is set and currently present.
    var priorityDevice: BTDevice? {
        guard !preferredDeviceName.isEmpty else { return nil }
        return devices.first {
            $0.name.caseInsensitiveCompare(preferredDeviceName) == .orderedSame
        }
    }

    var displayShort: String {
        if !isPoweredOn { return "off" }

        // Priority device mode: show just that device's battery.
        if !preferredDeviceName.isEmpty {
            if let dev = priorityDevice {
                if let b = dev.lowestBattery { return "\(b)%" }
                return "on"
            }
            return hasFreshData ? "—" : "…"
        }

        if !hasFreshData && devices.isEmpty { return "…" }
        if devices.isEmpty { return "0" }

        // Single device: drop the count — just show its battery, or nothing
        // (icon only) if it doesn't report battery.
        if devices.count == 1 {
            if let b = devices[0].lowestBattery { return "\(b)%" }
            return ""
        }

        if let low = lowestBattery { return "\(devices.count)·\(low)%" }
        return "\(devices.count)"
    }
}

/// Bluetooth data flow:
/// - `system_profiler SPBluetoothDataType -json` runs on a background queue every
///   `profilerInterval` seconds. This is the primary source — IOBluetooth's
///   `pairedDevices()` does not include iCloud-paired devices like AirPods, and
///   `isConnected()` lies for audio devices that aren't streaming. system_profiler
///   sees what the BT menu actually shows.
/// - IOBluetooth supplements with non-audio peripherals (mouse/keyboard) that
///   already exist in the local pairing table, in case profiler data is stale.
/// - Power state read from `IOBluetoothHostController` (cheap, every tick).
@MainActor
final class BluetoothService: ObservableObject {
    @Published private(set) var snapshot = BluetoothSnapshot()

    private var profilerDevices: [String: BTDevice] = [:]
    private var lastProfilerRun: Date?
    private let profilerInterval: TimeInterval = 8
    private var profilerTask: Task<Void, Never>?
    private var hasRunProfilerOnce = false

    /// Optional BLE scanner for AirPods/Beats. Owned by SamplerCoordinator so
    /// it survives across ticks.
    weak var airPodsScanner: AirPodsScanner?

    /// Generic BLE GATT Battery Service (0x180F) reader — works for any
    /// dual-mode device that advertises the standard BLE Battery Service.
    weak var bleBatteryReader: BLEBatteryReader?

    /// Called whenever the snapshot changes outside the regular sampler tick
    /// (e.g. async BLE update arrived). SamplerCoordinator wires this to its
    /// `onTick` so the menu bar label refreshes immediately.
    var onSnapshotChanged: (() -> Void)?

    private var scannerCancellables: Set<AnyCancellable> = []

    /// Re-subscribes to the currently-assigned scanners. Call after changing
    /// `airPodsScanner` / `bleBatteryReader`.
    func observeScanners() {
        scannerCancellables.removeAll()
        if let s = airPodsScanner {
            s.$readings.dropFirst().sink { [weak self] _ in
                Task { @MainActor in
                    self?.rebuildSnapshot()
                    self?.onSnapshotChanged?()
                }
            }.store(in: &scannerCancellables)
        }
        if let r = bleBatteryReader {
            r.$readings.dropFirst().sink { [weak self] _ in
                Task { @MainActor in
                    self?.rebuildSnapshot()
                    self?.onSnapshotChanged?()
                }
            }.store(in: &scannerCancellables)
        }
        // Force an immediate rebuild so the popover/bar reflect any data the
        // scanners may already have cached at subscription time.
        rebuildSnapshot()
        onSnapshotChanged?()
    }

    func tick() {
        rebuildSnapshot()
        maybeRefreshProfiler()
    }

    private func rebuildSnapshot() {
        // Power state inferred from the BLE scanner (avoids loading IOBluetooth).
        // If the scanner is enabled and CoreBluetooth reports poweredOn, BT is on.
        // If scanner is disabled (user opted out), we assume on so we don't show
        // "off" misleadingly — the user simply chose not to scan.
        let powered = bleBatteryReader?.isPoweredOn ?? true

        // Start with profiler results (the primary source — also covers anything
        // IOBluetooth used to supplement).
        var byAddress: [String: BTDevice] = profilerDevices.filter { $0.value.isConnected }

        // Merge battery readings from local sources (DeviceCache plist + IORegistry).
        // These catch AirPods, Magic Mouse/Keyboard, BLE peripherals — devices
        // whose battery isn't always in the system_profiler JSON.
        let localBatteries = BluetoothBatterySources.collect()
        for (address, reading) in localBatteries {
            guard var dev = byAddress[address] else { continue }
            dev.battery      = dev.battery      ?? reading.single
            dev.batteryLeft  = dev.batteryLeft  ?? reading.left
            dev.batteryRight = dev.batteryRight ?? reading.right
            dev.batteryCase  = dev.batteryCase  ?? reading.caseLevel
            byAddress[address] = dev
        }

        // Merge AirPods/Beats BLE Continuity readings. We match by name fuzzy
        // (BLE address differs from classic BT address). If we find a match,
        // overlay batteries; otherwise add as a virtual entry so the user sees
        // the device even when not paired classically.
        // Merge generic GATT Battery Service (0x180F) readings. Match by name —
        // BLE peripheral name typically equals the classic BT name.
        if let ble = bleBatteryReader {
            for reading in ble.readings {
                let needle = reading.name.lowercased()
                let matchKey = byAddress.first { _, dev in
                    dev.name.lowercased() == needle ||
                    dev.name.lowercased().contains(needle) ||
                    needle.contains(dev.name.lowercased())
                }?.key
                if let key = matchKey, var dev = byAddress[key] {
                    dev.battery = dev.battery ?? reading.percent
                    byAddress[key] = dev
                } else {
                    // Discovered over the air but not in the profiler's
                    // connected list — mark unconfirmed so the "connected only"
                    // filter can hide it.
                    let virt = BTDevice(
                        id: "ble-\(reading.identifier.uuidString.prefix(8))",
                        name: reading.name,
                        kind: BluetoothService.classify(name: reading.name),
                        isConnected: false,
                        battery: reading.percent
                    )
                    byAddress[virt.id] = virt
                }
            }
        }

        if let scanner = airPodsScanner {
            for ap in scanner.readings {
                let needle = ap.modelName.lowercased()
                let matchKey: String? = byAddress.first { (_, dev) in
                    let hay = dev.name.lowercased()
                    return (hay.contains("airpod") && needle.contains("airpod"))
                        || (hay.contains("beats")  && needle.contains("beats"))
                        || hay == needle
                }?.key
                if let key = matchKey, var dev = byAddress[key] {
                    dev.batteryLeft  = dev.batteryLeft  ?? ap.leftPercent
                    dev.batteryRight = dev.batteryRight ?? ap.rightPercent
                    dev.batteryCase  = dev.batteryCase  ?? ap.casePercent
                    if dev.kind == BTDevice.Kind.other { dev.kind = .earbuds }
                    byAddress[key] = dev
                } else {
                    // AirPods seen via Continuity ads but not connected to this
                    // Mac (e.g. paired to an iPhone nearby).
                    let virt = BTDevice(
                        id: ap.stableId,
                        name: ap.modelName,
                        kind: .earbuds,
                        isConnected: false,
                        battery: nil,
                        batteryLeft: ap.leftPercent,
                        batteryRight: ap.rightPercent,
                        batteryCase: ap.casePercent
                    )
                    byAddress[ap.stableId] = virt
                }
            }
        }

        var devices = Array(byAddress.values)

        // "Connected devices only" — hide devices discovered over the air that
        // aren't actually connected to this Mac.
        if UserDefaults.standard.bool(forKey: FeaturePrefs.bluetoothConnectedOnlyKey) {
            devices = devices.filter { $0.isConnected }
        }

        devices.sort { lhs, rhs in
            // Lower battery first, then alphabetical.
            switch (lhs.lowestBattery, rhs.lowestBattery) {
            case let (l?, r?): if l != r { return l < r }
            case (nil, _?): return false
            case (_?, nil): return true
            default: break
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        // Remember connected device names (cumulative, capped) so the Settings
        // priority-device picker has a list even when devices come and go.
        let connectedNames = devices.filter(\.isConnected).map(\.name)
        if !connectedNames.isEmpty {
            var known = UserDefaults.standard.stringArray(forKey: FeaturePrefs.bluetoothKnownDevicesKey) ?? []
            for n in connectedNames where !known.contains(n) { known.append(n) }
            UserDefaults.standard.set(Array(known.suffix(16)), forKey: FeaturePrefs.bluetoothKnownDevicesKey)
        }

        snapshot = BluetoothSnapshot(
            isPoweredOn: powered,
            devices: devices,
            hasFreshData: hasRunProfilerOnce,
            preferredDeviceName: UserDefaults.standard.string(forKey: FeaturePrefs.bluetoothPriorityKey) ?? ""
        )
    }

    private func maybeRefreshProfiler() {
        if profilerTask != nil { return }
        if let last = lastProfilerRun, Date().timeIntervalSince(last) < profilerInterval { return }
        lastProfilerRun = Date()

        profilerTask = Task.detached(priority: .background) { [weak self] in
            let parsed = BluetoothService.runProfiler()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.profilerDevices = parsed
                self.hasRunProfilerOnce = true
                self.profilerTask = nil
                self.rebuildSnapshot()
            }
        }
    }

    private func normalizeAddress(_ raw: String) -> String {
        raw.lowercased().replacingOccurrences(of: ":", with: "-")
    }

    // MARK: - system_profiler

    nonisolated private static func runProfiler() -> [String: BTDevice] {
        let proc = Process()
        proc.launchPath = "/usr/sbin/system_profiler"
        proc.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return [:] }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return parseProfiler(data: data)
    }

    /// Two known shapes for `SPBluetoothDataType`:
    ///   modern (macOS 12+):
    ///     [{ "device_title": [ {"AirPods Pro": {…, "device_connected": "attrib_Yes", …}} ] }]
    ///   legacy:
    ///     [{ "device_connected": [ {"AirPods Pro": {…}} ],
    ///        "device_not_connected": [ … ] }]
    /// We accept both.
    nonisolated static func parseProfiler(data: Data) -> [String: BTDevice] {
        guard let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = any["SPBluetoothDataType"] as? [[String: Any]]
        else { return [:] }

        var out: [String: BTDevice] = [:]

        func ingest(name rawName: String, info: [String: Any], assumedConnected: Bool?) {
            let addressRaw = (info["device_address"] as? String) ?? ""
            guard !addressRaw.isEmpty else { return }
            let address = addressRaw.lowercased().replacingOccurrences(of: ":", with: "-")

            let connected: Bool = {
                if let a = assumedConnected { return a }
                if let v = info["device_connected"] as? String {
                    return v.lowercased().contains("yes") || v.lowercased().contains("true")
                }
                return false
            }()

            var d = BTDevice(
                id: address,
                name: rawName,
                kind: classify(name: rawName, minorType: info["device_minorType"] as? String),
                isConnected: connected
            )

            // Battery keys vary across macOS versions.
            let mainKeys   = ["device_batteryLevelMain", "device_batteryLevelSingle",
                              "device_batteryPercent", "device_BatteryPercent"]
            let leftKeys   = ["device_batteryLevelLeft",  "device_BatteryPercentLeft"]
            let rightKeys  = ["device_batteryLevelRight", "device_BatteryPercentRight"]
            let caseKeys   = ["device_batteryLevelCase",  "device_BatteryPercentCase"]

            d.battery      = firstPercent(info, keys: mainKeys)
            d.batteryLeft  = firstPercent(info, keys: leftKeys)
            d.batteryRight = firstPercent(info, keys: rightKeys)
            d.batteryCase  = firstPercent(info, keys: caseKeys)

            out[address] = d
        }

        func ingestList(_ list: [[String: Any]], assumedConnected: Bool?) {
            for entry in list {
                for (rawName, rawInfo) in entry {
                    guard let info = rawInfo as? [String: Any] else { continue }
                    ingest(name: rawName, info: info, assumedConnected: assumedConnected)
                }
            }
        }

        for section in arr {
            if let modern = section["device_title"] as? [[String: Any]] {
                ingestList(modern, assumedConnected: nil)   // read flag from each entry
            }
            if let connected = section["device_connected"] as? [[String: Any]] {
                ingestList(connected, assumedConnected: true)
            }
            if let notConnected = section["device_not_connected"] as? [[String: Any]] {
                ingestList(notConnected, assumedConnected: false)
            }
        }
        return out
    }

    nonisolated private static func firstPercent(_ info: [String: Any], keys: [String]) -> Int? {
        for k in keys {
            if let s = info[k] as? String, let p = pct(s) { return p }
            if let n = info[k] as? Int { return n }
        }
        return nil
    }

    nonisolated private static func pct(_ s: String) -> Int? {
        Int(s.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }

    // MARK: - Classification

    nonisolated static func classify(name: String, classOfDevice: UInt32 = 0, minorType: String? = nil) -> BTDevice.Kind {
        let lower = name.lowercased()
        if let m = minorType?.lowercased() {
            if m.contains("headphone") || m.contains("headset") {
                return (lower.contains("pod") || lower.contains("bud")) ? .earbuds : .headphones
            }
            if m.contains("speaker")  { return .speaker }
            if m.contains("mouse")    { return .mouse }
            if m.contains("keyboard") { return .keyboard }
            if m.contains("game") || m.contains("controller") { return .controller }
            if m.contains("phone")    { return .phone }
            if m.contains("watch")    { return .watch }
        }

        let major = (classOfDevice >> 8) & 0x1F
        let minor = (classOfDevice >> 2) & 0x3F
        switch major {
        case 0x02: return .phone
        case 0x04:
            if minor == 0x01 || minor == 0x02 || minor == 0x06 { return .headphones }
            if minor == 0x05 || minor == 0x07 { return .speaker }
            return .speaker
        case 0x05:
            if (minor & 0x10) != 0 { return .keyboard }
            if (minor & 0x20) != 0 { return .mouse }
            return .controller
        default: break
        }

        if lower.contains("airpod") || lower.contains("buds") || lower.contains("earbud") { return .earbuds }
        if lower.contains("headphone") || lower.contains("headset") || lower.contains("wh-") || lower.contains("qc") { return .headphones }
        if lower.contains("speaker") || lower.contains("homepod") || lower.contains("sonos") { return .speaker }
        if lower.contains("magic mouse") || lower.contains("trackpad") || lower.contains("mouse") { return .mouse }
        if lower.contains("keyboard") { return .keyboard }
        if lower.contains("controller") || lower.contains("dualsense") || lower.contains("xbox") || lower.contains("joy-con") { return .controller }
        if lower.contains("watch") { return .watch }
        if lower.contains("iphone") || lower.contains("ipad") { return .phone }
        return .other
    }
}

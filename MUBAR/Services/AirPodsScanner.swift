import Foundation
import CoreBluetooth

/// Reads battery for AirPods / Beats H1·W1·H2 devices by passively scanning
/// Apple's Continuity BLE advertisements (manufacturer ID 0x004C, sub-type 0x07
/// "Proximity Pairing"). Works even when the device is paired to a different
/// Apple account / phone — we're just sniffing public BLE traffic.
///
/// Layout (after `FF 4C 00`):
///   [0]    0x07              subtype = ProximityPairing
///   [1]    0x19              length = 25
///   [2]    paired flag (1 = paired/active)
///   [3-4]  model id (2 bytes, big-endian)
///   [5]    status: bit 0x20 → primary is left
///   [6]    nibbles: lo = pod1 battery, hi = pod2 battery (0..10 ×10%, 0xF = unknown)
///   [7]    nibbles: lo = case battery, hi = charging flags (bit 0x10 pod1, 0x20 pod2, 0x40 case)
///   [8]    lid-open counter
///   [9..]  AES-encrypted hash (we ignore)
struct AirPodsReading: Equatable {
    var modelName: String
    var modelId: UInt16
    var leftPercent: Int?
    var rightPercent: Int?
    var casePercent: Int?
    var leftCharging: Bool = false
    var rightCharging: Bool = false
    var caseCharging: Bool = false
    var lastSeen: Date

    var stableId: String { String(format: "airpods-%04x", modelId) }
}

@MainActor
final class AirPodsScanner: NSObject, ObservableObject {
    @Published private(set) var readings: [AirPodsReading] = []

    private var central: CBCentralManager!
    private var byModelId: [UInt16: AirPodsReading] = [:]
    private let staleAfter: TimeInterval = 90
    private var isEnabled = true

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: DispatchQueue(label: "mubar.airpods.ble"),
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    /// Toggle scanning. When disabled, the radio is freed and we drop cached
    /// readings on the next prune cycle. The CBCentralManager itself is kept —
    /// re-creating it would re-trigger the permission prompt.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            startScanIfReady()
        } else {
            if central.isScanning { central.stopScan() }
            byModelId.removeAll()
            readings.removeAll()
        }
    }

    // MARK: - Helpers

    private func startScanIfReady() {
        guard isEnabled, central.state == .poweredOn else { return }
        // We don't filter by service UUID — Continuity ads have no service.
        // We need duplicates so battery updates keep arriving.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    private func pruneStale() {
        let cutoff = Date().addingTimeInterval(-staleAfter)
        byModelId = byModelId.filter { $0.value.lastSeen >= cutoff }
        readings = Array(byModelId.values).sorted { $0.modelName < $1.modelName }
    }

    fileprivate func merge(_ r: AirPodsReading) {
        byModelId[r.modelId] = r
        readings = Array(byModelId.values).sorted { $0.modelName < $1.modelName }
    }
}

extension AirPodsScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in self.startScanIfReady() }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String : Any],
                                     rssi RSSI: NSNumber) {
        guard let mfr = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return }
        guard let reading = AirPodsScanner.decode(manufacturerData: mfr) else { return }
        Task { @MainActor in
            self.merge(reading)
            self.pruneStale()
        }
    }

    // MARK: - Decoder

    nonisolated static func decode(manufacturerData data: Data) -> AirPodsReading? {
        // Apple manufacturer prefix is the first 2 bytes of the framework-stripped
        // payload: 0x4C 0x00 (little-endian Apple ID 0x004C). After that the
        // Continuity TLV stream starts. We look for a 0x07 record of length 0x19.
        guard data.count >= 2 + 27 else { return nil }
        guard data[0] == 0x4C, data[1] == 0x00 else { return nil }

        var i = 2
        while i + 1 < data.count {
            let type = data[i]
            let len  = Int(data[i + 1])
            let bodyStart = i + 2
            let bodyEnd = bodyStart + len
            guard bodyEnd <= data.count else { return nil }

            if type == 0x07 && len == 0x19 {
                return parseProximity(Array(data[bodyStart..<bodyEnd]))
            }
            i = bodyEnd
        }
        return nil
    }

    nonisolated private static func parseProximity(_ b: [UInt8]) -> AirPodsReading? {
        guard b.count >= 9 else { return nil }

        let modelId = (UInt16(b[1]) << 8) | UInt16(b[2])
        let status  = b[3]
        let podByte = b[4]
        let caseByte = b[5]

        let primaryLeft = (status & 0x20) != 0
        let podOne = nibbleToPercent(podByte & 0x0F)
        let podTwo = nibbleToPercent(podByte >> 4)
        let caseLevel = nibbleToPercent(caseByte & 0x0F)

        let chargeBits = caseByte >> 4
        let podOneCharging = (chargeBits & 0x01) != 0
        let podTwoCharging = (chargeBits & 0x02) != 0
        let caseCharging   = (chargeBits & 0x04) != 0

        let left   = primaryLeft ? podOne : podTwo
        let right  = primaryLeft ? podTwo : podOne
        let lcharg = primaryLeft ? podOneCharging : podTwoCharging
        let rcharg = primaryLeft ? podTwoCharging : podOneCharging

        return AirPodsReading(
            modelName: AppleDeviceCatalog.name(for: modelId),
            modelId: modelId,
            leftPercent: left,
            rightPercent: right,
            casePercent: caseLevel,
            leftCharging: lcharg,
            rightCharging: rcharg,
            caseCharging: caseCharging,
            lastSeen: Date()
        )
    }

    nonisolated private static func nibbleToPercent(_ n: UInt8) -> Int? {
        if n == 0xF { return nil }     // unknown
        return min(Int(n) * 10, 100)   // 0..10 → 0..100
    }
}

/// Mapping from Apple device model identifier (the 2 bytes embedded in the
/// Continuity ad) to a friendly name.
enum AppleDeviceCatalog {
    static let table: [UInt16: String] = [
        0x0220: "AirPods (1st gen)",
        0x0F20: "AirPods (2nd gen)",
        0x1320: "AirPods (3rd gen)",
        0x1420: "AirPods (3rd gen)",
        0x2024: "AirPods (4th gen)",
        0x2724: "AirPods (4th gen, ANC)",
        0x0E20: "AirPods Pro",
        0x2420: "AirPods Pro (2nd gen)",
        0x2014: "AirPods Pro (2nd gen)",
        0x2124: "AirPods Pro (2nd gen, USB-C)",
        0x0A20: "AirPods Max",
        0x1F20: "AirPods Max",
        0x0520: "Powerbeats 3",
        0x0B20: "Powerbeats Pro",
        0x0C20: "Beats Solo Pro",
        0x1120: "Beats Studio Buds",
        0x1620: "Beats Studio Buds+",
        0x1220: "Beats Flex",
        0x1020: "Beats Solo3",
        0x0620: "Beats Studio3",
        0x1720: "Beats Fit Pro",
        0x1820: "Beats Studio Pro",
    ]

    static func name(for id: UInt16) -> String {
        table[id] ?? String(format: "Apple BLE device 0x%04X", id)
    }
}

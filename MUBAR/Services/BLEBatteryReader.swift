import Foundation
import CoreBluetooth

/// Connects to any BLE peripheral that advertises the standard GATT Battery
/// Service (0x180F), reads characteristic 0x2A19, and subscribes for live
/// updates. This works for a huge fraction of modern wireless devices —
/// dual-mode earbuds (EarFun, JBL, Anker, Bose newer models), BLE controllers,
/// fitness trackers, and many keyboards/mice — because the GATT Battery
/// Service is the universal BLE standard.
///
/// Scope: passive scan + on-demand connect. We disconnect after each read
/// unless the device pushes notifications (most do). Resampling cadence is
/// driven by the SamplerCoordinator tick.
struct BLEBatteryReading: Equatable {
    let name: String
    let identifier: UUID            // CoreBluetooth peripheral UUID (stable per Mac)
    let address: String?            // public BD address if exposed (lowercase, dash-separated)
    var percent: Int
    var lastUpdate: Date
}

@MainActor
final class BLEBatteryReader: NSObject, ObservableObject {
    @Published private(set) var readings: [BLEBatteryReading] = []

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var byId: [UUID: BLEBatteryReading] = [:]
    private var connecting: Set<UUID> = []
    private let staleAfter: TimeInterval = 600          // 10 min
    private var isEnabled = true

    /// True when the BT radio is powered on (read by BluetoothService for the
    /// "off" indicator, avoiding the need to load IOBluetooth.framework).
    var isPoweredOn: Bool { central?.state == .poweredOn }

    /// Toggle scanning. When disabled the radio stops, all in-flight
    /// connections are cancelled, and cached readings are dropped.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            startScan()
        } else {
            if central.isScanning { central.stopScan() }
            for (_, p) in peripherals where p.state != .disconnected {
                central.cancelPeripheralConnection(p)
            }
            peripherals.removeAll()
            connecting.removeAll()
            byId.removeAll()
            readings.removeAll()
        }
    }

    nonisolated(unsafe) private static let batteryService        = CBUUID(string: "180F")
    nonisolated(unsafe) private static let batteryCharacteristic = CBUUID(string: "2A19")

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: DispatchQueue(label: "mubar.ble.battery"),
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    fileprivate func startScan() {
        guard isEnabled, central.state == .poweredOn else { return }
        // Only scan for peripherals advertising the Battery Service. This
        // filter is honored by the system at the radio level — much more
        // efficient than scanning for everything.
        central.scanForPeripherals(
            withServices: [Self.batteryService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    fileprivate func upsert(_ r: BLEBatteryReading) {
        byId[r.identifier] = r
        let cutoff = Date().addingTimeInterval(-staleAfter)
        byId = byId.filter { $0.value.lastUpdate >= cutoff }
        readings = Array(byId.values).sorted { $0.name < $1.name }
    }
}

extension BLEBatteryReader: CBCentralManagerDelegate, CBPeripheralDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in self.startScan() }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String : Any],
                                     rssi RSSI: NSNumber) {
        Task { @MainActor in
            // Save reference (CBCentralManager requires we retain the peripheral).
            self.peripherals[peripheral.identifier] = peripheral
            // Connect once per peripheral; the delegate will then drive discovery.
            guard peripheral.state == .disconnected,
                  !self.connecting.contains(peripheral.identifier) else { return }
            self.connecting.insert(peripheral.identifier)
            peripheral.delegate = self
            self.central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.connecting.remove(peripheral.identifier)
            peripheral.delegate = self
            peripheral.discoverServices([Self.batteryService])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in self.connecting.remove(peripheral.identifier) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in self.connecting.remove(peripheral.identifier) }
    }

    // MARK: - CBPeripheralDelegate

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else {
            // No battery service after all (advertising filter is hint-level on
            // some devices). Drop the connection — don't waste a slot.
            Task { @MainActor in self.central.cancelPeripheralConnection(peripheral) }
            return
        }
        peripheral.discoverCharacteristics([Self.batteryCharacteristic], for: svc)
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let ch = service.characteristics?.first(where: { $0.uuid == Self.batteryCharacteristic }) else {
            Task { @MainActor in self.central.cancelPeripheralConnection(peripheral) }
            return
        }
        peripheral.readValue(for: ch)
        if ch.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: ch)
            // Stay connected so we receive updates pushed by the device.
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.batteryCharacteristic,
              let data = characteristic.value, let byte = data.first
        else { return }
        let percent = Int(byte)
        let name = peripheral.name ?? "Unknown BLE device"
        let id = peripheral.identifier
        Task { @MainActor in
            let reading = BLEBatteryReading(
                name: name,
                identifier: id,
                address: nil,
                percent: percent,
                lastUpdate: Date()
            )
            self.upsert(reading)
            // If the characteristic doesn't notify, disconnect to free the radio
            // slot — we'll reconnect on next discovery.
            if !characteristic.properties.contains(.notify) {
                self.central.cancelPeripheralConnection(peripheral)
            }
        }
    }
}

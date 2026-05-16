import Foundation
import Combine

/// Single timer ticking at 1 Hz. Each tick decides per-service whether enough
/// time has elapsed since that service's last refresh to tick it again. This
/// gives us sub-second responsiveness for services that want it (Realtime preset)
/// without paying the cost of high-frequency syscalls for services that don't.
@MainActor
final class SamplerCoordinator: ObservableObject {
    let battery          = BatteryService()
    let cpu              = CPUService()
    let memory           = MemoryService()
    let network          = NetworkService()
    let disk             = DiskService()
    let bluetooth        = BluetoothService()

    /// BLE scanners are lazy: only instantiated when Bluetooth scanning is on.
    /// Each holds a CBCentralManager which keeps a connection to bluetoothd
    /// and allocates BLE buffers — together a meaningful chunk of RSS.
    private var airPodsScanner:   AirPodsScanner?
    private var bleBatteryReader: BLEBatteryReader?

    /// Called on the main actor after every tick. AppDelegate hooks this
    /// to refresh the status item's attributed title.
    var onTick: (() -> Void)?

    private var timer: Timer?
    private let baseInterval: TimeInterval = 1.0
    private var lastTick: [StatKind: Date] = [:]
    private var defaultsObserver: NSObjectProtocol?

    init() {
        StatPrefs.registerDefaults()
        MaterialMode.registerDefault()
        IntervalPrefs.registerDefaults()
        FeaturePrefs.registerDefaults()
        AppearancePrefs.registerDefaults()

        bluetooth.onSnapshotChanged = { [weak self] in self?.onTick?() }
        applyBluetoothScanningPreference()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyBluetoothScanningPreference() }
        }

        start()
        // Prime everything so the popover isn't empty on first open.
        for k in StatKind.allCases { tickService(k, force: true) }
    }

    deinit {
        timer?.invalidate()
        if let o = defaultsObserver { NotificationCenter.default.removeObserver(o) }
    }

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: baseInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = Date()
        for k in StatKind.allCases {
            let last = lastTick[k] ?? .distantPast
            if now.timeIntervalSince(last) + 0.05 >= IntervalPrefs.interval(for: k) {
                tickService(k, force: false)
            }
        }
        onTick?()
    }

    private func tickService(_ k: StatKind, force: Bool) {
        switch k {
        case .battery:   battery.tick()
        case .cpu:       cpu.tick()
        case .memory:    memory.tick()
        case .network:   network.tick()
        case .disk:      disk.tick()
        case .bluetooth: bluetooth.tick()
        }
        lastTick[k] = Date()
    }

    // MARK: - Memory: stop BLE scanners when user disables Bluetooth scanning

    private func applyBluetoothScanningPreference() {
        let enabled = UserDefaults.standard.bool(forKey: FeaturePrefs.bluetoothScanningKey)
        if enabled {
            if airPodsScanner == nil { airPodsScanner = AirPodsScanner() }
            if bleBatteryReader == nil { bleBatteryReader = BLEBatteryReader() }
            airPodsScanner?.setEnabled(true)
            bleBatteryReader?.setEnabled(true)
            bluetooth.airPodsScanner   = airPodsScanner
            bluetooth.bleBatteryReader = bleBatteryReader
        } else {
            airPodsScanner?.setEnabled(false)
            bleBatteryReader?.setEnabled(false)
            airPodsScanner = nil
            bleBatteryReader = nil
            bluetooth.airPodsScanner = nil
            bluetooth.bleBatteryReader = nil
        }
        // Re-subscribe BluetoothService to whichever scanners are now active so
        // their async readings push straight into the snapshot — no waiting for
        // the next bluetooth tick.
        bluetooth.observeScanners()
    }
}

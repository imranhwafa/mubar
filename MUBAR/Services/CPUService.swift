import Foundation
import Darwin

struct CPUSnapshot: Equatable {
    /// 0–100, system + user combined.
    var busyPercent: Double = 0
    var userPercent: Double = 0
    var systemPercent: Double = 0
    var coreCount: Int = ProcessInfo.processInfo.activeProcessorCount

    var displayShort: String { String(format: "%.0f%%", busyPercent) }
}

@MainActor
final class CPUService: ObservableObject {
    @Published private(set) var snapshot = CPUSnapshot()

    private var prevTicks: [UInt32: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = [:]

    func tick() {
        var count: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t!

        let kr = host_processor_info(mach_host_self(),
                                     PROCESSOR_CPU_LOAD_INFO,
                                     &cpuCount,
                                     &infoArray,
                                     &count)
        guard kr == KERN_SUCCESS else { return }

        defer {
            let size = vm_size_t(MemoryLayout<integer_t>.stride) * vm_size_t(count)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: infoArray), size)
        }

        var totalUser: UInt64 = 0, totalSystem: UInt64 = 0, totalIdle: UInt64 = 0, totalNice: UInt64 = 0

        for i in 0..<Int(cpuCount) {
            let base = i * Int(CPU_STATE_MAX)
            let user   = UInt32(bitPattern: infoArray[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: infoArray[base + Int(CPU_STATE_SYSTEM)])
            let idle   = UInt32(bitPattern: infoArray[base + Int(CPU_STATE_IDLE)])
            let nice   = UInt32(bitPattern: infoArray[base + Int(CPU_STATE_NICE)])

            let prev = prevTicks[UInt32(i)] ?? (user, system, idle, nice)
            prevTicks[UInt32(i)] = (user, system, idle, nice)

            totalUser   &+= UInt64(user   &- prev.user)
            totalSystem &+= UInt64(system &- prev.system)
            totalIdle   &+= UInt64(idle   &- prev.idle)
            totalNice   &+= UInt64(nice   &- prev.nice)
        }

        let total = totalUser + totalSystem + totalIdle + totalNice
        guard total > 0 else { return }

        let busy = totalUser + totalSystem + totalNice
        snapshot = CPUSnapshot(
            busyPercent: Double(busy) / Double(total) * 100.0,
            userPercent: Double(totalUser + totalNice) / Double(total) * 100.0,
            systemPercent: Double(totalSystem) / Double(total) * 100.0
        )
    }
}

import Foundation
import Darwin

struct MemorySnapshot: Equatable {
    var totalBytes: UInt64 = 0
    var usedBytes: UInt64 = 0
    var pressurePercent: Double = 0    // used / total * 100

    var displayShort: String { String(format: "%.0f%%", pressurePercent) }

    var displayLong: String {
        "\(ByteFormat.binary(usedBytes)) / \(ByteFormat.binary(totalBytes))"
    }
}

@MainActor
final class MemoryService: ObservableObject {
    @Published private(set) var snapshot = MemorySnapshot()

    private let pageSize: UInt64 = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return UInt64(size)
    }()

    private let totalBytes: UInt64 = {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &len, nil, 0)
        return size
    }()

    func tick() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }

        // "App Memory" approximation: active + wired + compressed
        let active     = UInt64(stats.active_count)
        let wired      = UInt64(stats.wire_count)
        let compressed = UInt64(stats.compressor_page_count)
        let used = (active + wired + compressed) * pageSize

        snapshot = MemorySnapshot(
            totalBytes: totalBytes,
            usedBytes: used,
            pressurePercent: totalBytes > 0 ? Double(used) / Double(totalBytes) * 100.0 : 0
        )
    }
}

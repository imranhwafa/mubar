import Foundation
import IOKit

struct DiskSnapshot: Equatable {
    var bytesPerSecondRead: UInt64 = 0
    var bytesPerSecondWrite: UInt64 = 0

    var displayShort: String {
        "R \(ByteFormat.rate(bytesPerSecondRead)) W \(ByteFormat.rate(bytesPerSecondWrite))"
    }
}

@MainActor
final class DiskService: ObservableObject {
    @Published private(set) var snapshot = DiskSnapshot()

    private var lastRead: UInt64 = 0
    private var lastWrite: UInt64 = 0
    private var lastSampleTime: Date?

    func tick() {
        let (read, write) = Self.totals()
        let now = Date()

        defer {
            lastRead = read
            lastWrite = write
            lastSampleTime = now
        }

        guard let prev = lastSampleTime else { return }
        let dt = max(now.timeIntervalSince(prev), 0.001)

        snapshot = DiskSnapshot(
            bytesPerSecondRead:  UInt64(Double(read  &- lastRead)  / dt),
            bytesPerSecondWrite: UInt64(Double(write &- lastWrite) / dt)
        )
    }

    private static func totals() -> (UInt64, UInt64) {
        var iter: io_iterator_t = 0
        let match = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iter) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iter) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        while case let service = IOIteratorNext(iter), service != 0 {
            defer { IOObjectRelease(service) }

            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any],
                  let stats = props["Statistics"] as? [String: Any]
            else { continue }

            if let r = stats["Bytes (Read)"]    as? UInt64 { totalRead  &+= r }
            if let w = stats["Bytes (Write)"]   as? UInt64 { totalWrite &+= w }
        }

        return (totalRead, totalWrite)
    }
}

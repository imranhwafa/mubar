import Foundation
import Darwin

struct NetworkSnapshot: Equatable {
    var bytesPerSecondIn: UInt64 = 0
    var bytesPerSecondOut: UInt64 = 0
    var primaryInterface: String = "—"

    var displayShort: String {
        "↓\(ByteFormat.rate(bytesPerSecondIn)) ↑\(ByteFormat.rate(bytesPerSecondOut))"
    }
}

@MainActor
final class NetworkService: ObservableObject {
    @Published private(set) var snapshot = NetworkSnapshot()

    private var lastIn: UInt64 = 0
    private var lastOut: UInt64 = 0
    private var lastSampleTime: Date?

    func tick() {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return }
        defer { freeifaddrs(ifaddrPtr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var primaryName = ""

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cursor {
            defer { cursor = p.pointee.ifa_next }
            let name = String(cString: p.pointee.ifa_name)

            // Skip loopback, virtual, awdl, llw, utun.
            if name.hasPrefix("lo") || name.hasPrefix("utun") ||
               name.hasPrefix("awdl") || name.hasPrefix("llw") ||
               name.hasPrefix("bridge") || name.hasPrefix("gif") ||
               name.hasPrefix("stf") || name.hasPrefix("anpi") ||
               name.hasPrefix("ap") {
                continue
            }

            guard let addr = p.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK) else { continue }

            guard let dataPtr = p.pointee.ifa_data else { continue }
            let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee

            // ifi_ibytes / ifi_obytes are typedefed as u_long which is 64-bit on macOS.
            totalIn  &+= UInt64(data.ifi_ibytes)
            totalOut &+= UInt64(data.ifi_obytes)

            if (name.hasPrefix("en") || name.hasPrefix("wl")) &&
                (data.ifi_ibytes > 0 || data.ifi_obytes > 0) {
                if primaryName.isEmpty { primaryName = name }
            }
        }

        let now = Date()
        defer {
            lastIn = totalIn
            lastOut = totalOut
            lastSampleTime = now
        }

        guard let prev = lastSampleTime else {
            snapshot = NetworkSnapshot(primaryInterface: primaryName.isEmpty ? "—" : primaryName)
            return
        }

        let dt = max(now.timeIntervalSince(prev), 0.001)
        let inRate  = UInt64(Double(totalIn  &- lastIn)  / dt)
        let outRate = UInt64(Double(totalOut &- lastOut) / dt)

        snapshot = NetworkSnapshot(
            bytesPerSecondIn: inRate,
            bytesPerSecondOut: outRate,
            primaryInterface: primaryName.isEmpty ? snapshot.primaryInterface : primaryName
        )
    }
}

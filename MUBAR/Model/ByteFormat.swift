import Foundation

enum ByteFormat {
    /// Binary (KiB/MiB/GiB) for sizes — used for RAM, disk capacity.
    static func binary(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowedUnits = [.useGB, .useMB, .useKB]
        f.includesUnit = true
        return f.string(fromByteCount: Int64(bytes))
    }

    /// Compact rate display for the menu bar. Always 3-4 chars wide.
    static func rate(_ bytesPerSecond: UInt64) -> String {
        let b = Double(bytesPerSecond)
        switch b {
        case 0..<1_024:                 return String(format: "%.0fB", b)
        case 0..<(1_024 * 1_024):       return String(format: "%.0fK", b / 1_024)
        case 0..<(1_024 * 1_024 * 100): return String(format: "%.1fM", b / (1_024 * 1_024))
        case 0..<(1_024 * 1_024 * 1_024): return String(format: "%.0fM", b / (1_024 * 1_024))
        default:                        return String(format: "%.1fG", b / (1_024 * 1_024 * 1_024))
        }
    }
}

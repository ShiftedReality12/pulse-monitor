import Foundation

public struct CPUTicks: Sendable {
    public let user, system, idle, nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64 = 0) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
    public func usage(since old: Self) -> Double? {
        // Kernel counters are uint32_t and wrap independently.
        func delta(_ value: UInt64, _ previous: UInt64) -> UInt64 { UInt64(UInt32(truncatingIfNeeded: value) &- UInt32(truncatingIfNeeded: previous)) }
        let busy = delta(user, old.user) + delta(system, old.system) + delta(nice, old.nice)
        let total = busy + delta(idle, old.idle)
        return total > 0 ? Double(busy) / Double(total) * 100 : nil
    }
}
public enum Pressure: String, Codable, Sendable {
    case normal = "Normal", warning = "Tight", critical = "Critical", unavailable = "Unavailable"
    public static func classify(_ level: Int) -> Self {
        switch level { case 1: .normal; case 2: .warning; case 4: .critical; default: .unavailable }
    }
}

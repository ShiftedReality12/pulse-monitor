import Foundation

/// Whole-process CPU credit: rendering/sampling spend the same window budget as scanning.
public struct DiskScanDuty: Sendable {
    private var wall = 0.0, cpu = 0.0, credit = 0.0
    public init() {}
    public mutating func reset(wall: Double, cpu: Double) { self.wall = wall; self.cpu = cpu; credit = 0 }
    public mutating func allowance(wall: Double, cpu: Double, fullWindow: Bool) -> Double {
        guard fullWindow else { return 0 } // Glance/menu only consumes saved totals.
        credit = min(0.02, credit + max(0, wall - self.wall) * 0.0195 - max(0, cpu - self.cpu))
        self.wall = wall; self.cpu = cpu
        return max(0, credit - 0.002)
    }
}

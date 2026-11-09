import Foundation

public enum HealthSignal: String, Codable, Sendable { case heat, memory, disk, cpu, unavailable, none }

/// Temporal signals use only observed samples; gaps reset continuous CPU evidence.
public struct VerdictTracker: Sendable {
    private var highCPUSince: TimeInterval?
    private var previousTime: TimeInterval?
    private var swapHistory: [(time: TimeInterval, bytes: UInt64)] = []
    public init() {}
    public mutating func apply(to snapshot: inout Snapshot, uptime: TimeInterval) {
        if let previousTime, uptime <= previousTime || uptime - previousTime > 10 {
            highCPUSince = nil
            swapHistory.removeAll(keepingCapacity: true)
        }
        if let cpu = snapshot.cpu, cpu > 85 {
            if highCPUSince == nil { highCPUSince = uptime }
            snapshot.highCPUDuration = uptime - (highCPUSince ?? uptime)
        } else { highCPUSince = nil; snapshot.highCPUDuration = 0 }
        swapHistory.removeAll { $0.time < uptime - 600 }
        if let swap = snapshot.swap {
            swapHistory.append((uptime, swap))
            if let first = swapHistory.first { snapshot.swapGrowthTenMinutes = swap > first.bytes ? swap - first.bytes : 0 }
        } else { swapHistory.removeAll(keepingCapacity: true); snapshot.swapGrowthTenMinutes = nil }
        previousTime = uptime
    }
}


import Foundation

public struct ImpactRanking: Sendable {
    private struct Terms: Sendable {
        var cpu: Double; var memory: Double; var writes: Double
        var score: Double { 100 * (0.40 * cpu + 0.55 * memory + 0.05 * writes) }
        func smoothed(from old: Self, elapsed: Double) -> Self {
            func blend(_ old: Double, _ new: Double, tau: Double) -> Double {
                old + (1 - exp(-elapsed / tau)) * (new - old)
            }
            return Self(cpu: blend(old.cpu, cpu, tau: 6), memory: blend(old.memory, memory, tau: 12), writes: blend(old.writes, writes, tau: 12))
        }
    }
    private var previous: [String: Terms] = [:]
    private var lastTime: TimeInterval?
    public init() {}
    /// CPU 40%, RAM 55% against min(physical, 16 GB), writes at most 5%.
    public mutating func rank(_ groups: [ProcessGroup], totalMemory: UInt64, cores: Int, uptime: TimeInterval) -> [ProcessGroup] {
        let elapsed = lastTime.map { max(0, uptime - $0) } ?? 0
        var next: [String: Terms] = [:]
        var result = groups.map { group in
            var group = group
            let raw = Self.terms(cpu: group.cpu, memory: group.resident, writes: group.writesPerSecond, totalMemory: totalMemory, cores: cores)
            let terms = group.hasVerifiedIdentity ? previous[group.id].map { raw.smoothed(from: $0, elapsed: elapsed) } ?? raw : raw
            if group.hasVerifiedIdentity { next[group.id] = terms }
            group.impact = terms.score
            return group
        }
        result.sort { $0.impact == $1.impact ? $0.id < $1.id : $0.impact > $1.impact }
        previous = next; lastTime = uptime
        return result
    }
    public static func score(cpu: Double?, memory: UInt64?, writes: Double?, totalMemory: UInt64, cores: Int) -> Double {
        terms(cpu: cpu, memory: memory, writes: writes, totalMemory: totalMemory, cores: cores).score
    }
    private static func terms(cpu: Double?, memory: UInt64?, writes: Double?, totalMemory: UInt64, cores: Int) -> Terms {
        func unit(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        return Terms(cpu: unit((cpu ?? 0) / (Double(max(1, cores)) * 100)),
                     memory: totalMemory > 0 ? unit(Double(memory ?? 0) / Double(min(totalMemory, 16_000_000_000))) : 0,
                     writes: unit(log1p(max(0, writes ?? 0) / 50_000_000) / log(11)))
    }
}

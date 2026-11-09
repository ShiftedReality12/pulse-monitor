import Foundation

/// One 30-second bucket. Pressure and thermal keep the worst level seen in the bucket so a brief spike is never averaged away.
public struct TimelineSample: Sendable, Equatable {
    public var time: Double
    public var pressure: UInt8
    public var swap: UInt64?
    public var compressed: UInt64?
    public var diskFree: UInt64?
    public var thermal: UInt8
    public var speedLimit: Int?
    public static let thermalUnknown: UInt8 = 255
    public static func thermalLevel(_ name: String) -> UInt8 {
        ["Nominal": 0, "Warm": 1, "Serious": 2, "Critical": 3][name] ?? thermalUnknown
    }
}
public struct ThermalEvent: Sendable, Equatable, Identifiable {
    public var start: Double
    public var end: Double?
    public var peak: UInt8
    public var lowestSpeedLimit: Int?
    public var id: Double { start }
    public var summary: String {
        let level = peak >= 3 ? "critical" : "serious"
        let limit = lowestSpeedLimit.flatMap { $0 < 100 ? ", CPU limited to \($0)%" : nil } ?? ""
        return "macOS reported \(level) heat\(limit)."
    }
}
/// Fixed-size ring of 30-second buckets (24 hours), in memory only. Cost never grows with uptime.
public struct TimelineStore: Sendable {
    public static let bucket = 30.0
    public static let maximumEvents = 50
    public let capacity: Int
    private var slots: [TimelineSample?]
    private var next = 0
    public private(set) var count = 0
    public private(set) var events: [ThermalEvent] = []
    public init(capacity: Int = 2880) {
        precondition(capacity > 0)
        self.capacity = capacity; slots = .init(repeating: nil, count: capacity)
    }
    static func rank(_ level: UInt8) -> Int { level == TimelineSample.thermalUnknown ? -1 : Int(level) }
    public static func isThrottling(thermal: UInt8, speedLimit: Int?) -> Bool {
        (thermal != TimelineSample.thermalUnknown && thermal >= 2) || (speedLimit.map { $0 < 100 } ?? false)
    }
    public mutating func record(time: Double, pressure: UInt8, swap: UInt64?, compressed: UInt64?, diskFree: UInt64?, thermal: UInt8, speedLimit: Int?) {
        let start = (time / Self.bucket).rounded(.down) * Self.bucket
        let last = (next + capacity - 1) % capacity
        if count > 0, let newest = slots[last], start < newest.time {
            // The wall clock moved backwards: older buckets would be out of order, so start the timeline again.
            slots = .init(repeating: nil, count: capacity); next = 0; count = 0
        }
        if count > 0, var sample = slots[last], sample.time == start {
            sample.pressure = max(sample.pressure, pressure)
            sample.swap = swap ?? sample.swap; sample.compressed = compressed ?? sample.compressed; sample.diskFree = diskFree ?? sample.diskFree
            if Self.rank(thermal) > Self.rank(sample.thermal) { sample.thermal = thermal }
            if let speedLimit { sample.speedLimit = min(sample.speedLimit ?? speedLimit, speedLimit) }
            slots[last] = sample
        } else {
            slots[next] = TimelineSample(time: start, pressure: pressure, swap: swap, compressed: compressed, diskFree: diskFree, thermal: thermal, speedLimit: speedLimit)
            next = (next + 1) % capacity; count = min(count + 1, capacity)
        }
        trackEvents(time: time, thermal: thermal, speedLimit: speedLimit)
    }
    private mutating func trackEvents(time: Double, thermal: UInt8, speedLimit: Int?) {
        let throttling = Self.isThrottling(thermal: thermal, speedLimit: speedLimit)
        let open = events.last?.end == nil && !events.isEmpty
        if throttling {
            if open {
                events[events.count - 1].peak = max(events[events.count - 1].peak, thermal == TimelineSample.thermalUnknown ? 0 : thermal)
                if let speedLimit { events[events.count - 1].lowestSpeedLimit = min(events[events.count - 1].lowestSpeedLimit ?? speedLimit, speedLimit) }
            } else {
                events.append(ThermalEvent(start: time, end: nil, peak: thermal == TimelineSample.thermalUnknown ? 2 : thermal, lowestSpeedLimit: speedLimit))
                if events.count > Self.maximumEvents { events.removeFirst(events.count - Self.maximumEvents) }
            }
        } else if open { events[events.count - 1].end = time }
    }
    /// Chronological copy of every retained bucket.
    public var samples: [TimelineSample] {
        let start = count == capacity ? next : 0
        return (0..<count).compactMap { slots[(start + $0) % capacity] }
    }
}
extension Pressure {
    public var level: UInt8 { switch self { case .normal: 1; case .warning: 2; case .critical: 4; case .unavailable: 0 } }
}
extension TimelineSample {
    /// Keeps at most `limit` samples, retaining the worst pressure/thermal level of each merged group.
    public static func reduce(_ samples: [TimelineSample], limit: Int) -> [TimelineSample] {
        precondition(limit >= 2)
        guard samples.count > limit else { return samples }
        var result: [TimelineSample] = []; result.reserveCapacity(limit)
        for bucket in 0..<limit {
            let lower = bucket * samples.count / limit, upper = max(lower + 1, (bucket + 1) * samples.count / limit)
            var merged = samples[min(upper, samples.count) - 1]
            for sample in samples[lower..<min(upper, samples.count)] {
                merged.pressure = max(merged.pressure, sample.pressure)
                if TimelineStore.rank(sample.thermal) > TimelineStore.rank(merged.thermal) { merged.thermal = sample.thermal }
                if let limit = sample.speedLimit { merged.speedLimit = min(merged.speedLimit ?? limit, limit) }
            }
            result.append(merged)
        }
        return result
    }
}

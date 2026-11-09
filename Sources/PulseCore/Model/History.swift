import Foundation

public struct HistorySample: Sendable, Equatable {
    public var date: Date
    public var memoryPercent, cpu, temperature, thermalSeverity, diskFree: Double?
    public init(_ snapshot: Snapshot) {
        date = snapshot.date; memoryPercent = snapshot.memoryPercent; cpu = snapshot.cpu
        temperature = snapshot.sensorSampleDate == nil || snapshot.sensorSampleDate == snapshot.date ? snapshot.effectiveTemperature : nil
        thermalSeverity = ["Nominal": 0.0, "Warm": 1.0, "Serious": 2.0, "Critical": 3.0][snapshot.thermal]
        diskFree = snapshot.diskFree.map(Double.init)
    }
}

/// Fixed slots: no process objects/strings and no per-tick array shifting.
public struct NumericHistory: Sendable {
    public let capacity: Int
    private var slots: [HistorySample?]
    private var next = 0
    public private(set) var count = 0
    public init(capacity: Int = 1801) {
        precondition(capacity > 0)
        self.capacity = capacity; slots = .init(repeating: nil, count: capacity)
    }
    public mutating func append(_ sample: HistorySample) {
        slots[next] = sample; next = (next + 1) % capacity; count = min(count + 1, capacity)
    }
    public func points(_ key: KeyPath<HistorySample, Double?>, limit: Int = 120) -> [PlotPoint] {
        precondition(limit >= 4)
        var values: [PlotPoint] = []; values.reserveCapacity(count)
        let start = count == capacity ? next : 0
        let latest = slots[(next + capacity - 1) % capacity]?.date ?? .distantPast
        for offset in 0..<count {
            if let sample = slots[(start + offset) % capacity], sample.date >= latest.addingTimeInterval(-3600), let value = sample[keyPath: key] {
                values.append(PlotPoint(date: sample.date, value: value))
            }
        }
        guard values.count > limit else { return values }
        // Preserve first/last and both extrema in each bucket, without averaged/invented metrics.
        var result = [values[0]]
        let buckets = (limit - 2) / 2
        for bucket in 0..<buckets {
            let lower = 1 + bucket * (values.count - 2) / buckets
            let upper = 1 + (bucket + 1) * (values.count - 2) / buckets
            let indices = lower..<upper
            if let low = indices.min(by: { values[$0].value < values[$1].value }), let high = indices.max(by: { values[$0].value < values[$1].value }) {
                for index in Set([low, high]).sorted() { result.append(values[index]) }
            }
        }
        result.append(values[values.count - 1]); return result
    }
}
public struct PlotPoint: Sendable, Equatable, Identifiable {
    public init(date: Date, value: Double) { self.date = date; self.value = value }
    public var date: Date
    public var value: Double
    public var id: Date { date }
}
public struct PlotHistory: Sendable, Equatable {
    public var memory: [PlotPoint] = [], cpu: [PlotPoint] = [], temperature: [PlotPoint] = [], thermal: [PlotPoint] = [], disk: [PlotPoint] = []
    public init() {}
    public init(_ history: NumericHistory) {
        memory = history.points(\.memoryPercent); cpu = history.points(\.cpu)
        temperature = history.points(\.temperature); thermal = history.points(\.thermalSeverity); disk = history.points(\.diskFree)
    }
}
public enum SamplingPolicy {
    public static func interval(visible: Bool) -> TimeInterval { visible ? 2 : 5 }
    /// Closed windows still refresh owners every 30 seconds so leak watch keeps its history.
    public static func processInterval(visible: Bool) -> TimeInterval { visible ? 6 : 30 }
    public static func leeway(visible: Bool) -> TimeInterval { visible ? 0.25 : 1 }
}

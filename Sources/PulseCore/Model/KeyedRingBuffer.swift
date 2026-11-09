import Foundation

/// Numeric or other Sendable observations, bounded per key and pruned to the supplied key set.
public struct KeyedRingBuffer<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    public struct Sample: Sendable {
        public let time: Double
        public let value: Value
    }
    private struct Ring: Sendable {
        var values: [Sample] = []
        var next = 0
        mutating func append(_ sample: Sample, capacity: Int) {
            if values.count < capacity { values.append(sample) }
            else { values[next] = sample }
            next = (next + 1) % capacity
        }
        func ordered(capacity: Int) -> [Sample] {
            values.count < capacity ? values : Array(values[next...] + values[..<next])
        }
    }
    private var rings: [Key: Ring] = [:]
    private let capacity: Int
    private let horizon: Double
    public var keys: Set<Key> { Set(rings.keys) }
    public init(capacity: Int = 60, horizon: Double = 60) {
        precondition(capacity > 0 && horizon > 0)
        self.capacity = capacity; self.horizon = horizon
    }
    public mutating func record(_ values: [Key: Value], at time: Double, retaining: Set<Key> = []) {
        rings = rings.filter { values[$0.key] != nil || retaining.contains($0.key) }
        for (key, value) in values { rings[key, default: Ring()].append(Sample(time: time, value: value), capacity: capacity) }
    }
    public func samples(for key: Key, at time: Double) -> [Sample] {
        (rings[key]?.ordered(capacity: capacity) ?? []).filter { $0.time >= time - horizon && $0.time <= time }
    }
}

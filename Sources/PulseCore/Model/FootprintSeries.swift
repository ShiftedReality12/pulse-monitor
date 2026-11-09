import Foundation

/// Real observations retain transient peaks; a point sample never erases its interval peak.
public struct FootprintSeries: Sendable {
    public struct Point: Sendable {
        public let elapsed: Double
        public let bytes: UInt64
        public let intervalPeak: UInt64
    }
    private let start: Double
    private let interval: Double
    private var next: Double
    private var intervalPeak: UInt64 = 0
    public private(set) var points: [Point] = []
    public private(set) var observations = 0
    public private(set) var missing = 0
    public private(set) var skippedIntervals = 0
    public private(set) var minimum: UInt64?
    public private(set) var maximum: UInt64?
    /// Nearest-rank p95 of the real two-second interval peaks, including transient spikes.
    public var percentile95: UInt64? {
        let peaks = points.map(\.intervalPeak).sorted()
        guard !peaks.isEmpty else { return nil }
        return peaks[max(0, Int(ceil(Double(peaks.count) * 0.95)) - 1)]
    }
    public init(start: Double, interval: Double = 2) {
        precondition(interval > 0)
        self.start = start; self.interval = interval; next = start + interval
    }
    public mutating func observe(at now: Double, bytes: UInt64?) {
        guard let bytes else { missing += 1; return }
        observations += 1
        minimum = min(minimum ?? bytes, bytes); maximum = max(maximum ?? bytes, bytes)
        intervalPeak = max(intervalPeak, bytes)
        if now >= next {
            let skipped = max(0, Int((now - next) / interval))
            skippedIntervals += skipped
            points.append(Point(elapsed: now - start, bytes: bytes, intervalPeak: intervalPeak))
            next += Double(skipped + 1) * interval; intervalPeak = 0
        }
    }
}

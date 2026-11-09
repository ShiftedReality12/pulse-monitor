import Foundation

public struct RunwayEstimate: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case unavailable
        case measuring(have: Double, need: Double)
        case growing(bytesPerHour: Double)
        case stable
        case shrinking(bytesPerHour: Double, daysToFull: Double, daysToFiveGB: Double)
    }
    public var state: State = .unavailable
    public var free: UInt64?
    public var basedOn: Double = 0
    public init() {}
    public init(state: State, free: UInt64?, basedOn: Double) { self.state = state; self.free = free; self.basedOn = basedOn }
    public var headline: String {
        switch state {
        case .unavailable: "Free space unavailable"
        case let .measuring(have, need): "Measuring: \(Int(have / 60)) of \(Int(need / 60)) minutes of readings"
        case .growing, .stable: free == 0 ? "Disk is full" : "Stable: free space is not shrinking"
        case let .shrinking(_, days, _): free == 0 ? "Disk is full" : "Full " + Self.until(days)
        }
    }
    public var detail: String {
        let window = basedOn >= 3600 ? String(format: "%.1f hours", basedOn / 3600) : "\(Int(basedOn / 60)) minutes"
        switch state {
        case .unavailable: return "macOS did not report free space for the startup disk."
        case .measuring: return "Pulse needs a little history before it can estimate a fill rate."
        case let .growing(rate): return "Free space grew about \(Self.rate(rate)) over the last \(window)."
        case .stable: return "No meaningful change over the last \(window)."
        case let .shrinking(rate, _, five): return "Filling at about \(Self.rate(rate)) over the last \(window). " + (five <= 0 ? "Already under 5 GB free." : "Down to 5 GB free " + Self.until(five) + ".")
        }
    }
    public var perHour: Double? {
        switch state { case let .shrinking(rate, _, _): -rate; case let .growing(rate): rate; case .stable: 0; default: nil }
    }
    static func rate(_ bytesPerHour: Double) -> String {
        let value = abs(bytesPerHour)
        return value >= 1e9 ? String(format: "%.1f GB/hour", value / 1e9) : String(format: "%.0f MB/hour", value / 1e6)
    }
    static func until(_ days: Double) -> String { days * 24 < 1 ? "in under an hour" : "in about " + span(days) }
    static func span(_ days: Double) -> String {
        if days < 1 { let hours = max(1, Int((days * 24).rounded())); return hours == 1 ? "1 hour" : "\(hours) hours" }
        let whole = Int(days.rounded())
        return whole == 1 ? "1 day" : "\(whole) days"
    }
}
/// Least-squares fill rate over the newest six hours of 30-second readings.
public enum DiskRunway {
    public static let minimumSpan = 600.0
    public static let window = 6.0 * 3600
    public static let stableBytesPerHour = 1_000_000.0
    public static let horizonDays = 365.0
    public static func estimate(samples: [TimelineSample], now: Double) -> RunwayEstimate {
        let points = samples.compactMap { sample in sample.diskFree.map { (time: sample.time, free: Double($0)) } }.filter { $0.time >= now - window }
        guard let latest = points.last, let first = points.first else { return RunwayEstimate() }
        let span = latest.time - first.time
        let free = UInt64(max(0, latest.free))
        guard span >= minimumSpan else { return RunwayEstimate(state: .measuring(have: span, need: minimumSpan), free: free, basedOn: span) }
        let n = Double(points.count)
        let xs = points.map { ($0.time - first.time) / 3600 }, ys = points.map(\.free)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        let denominator = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard denominator > 0 else { return RunwayEstimate(state: .stable, free: free, basedOn: span) }
        let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) } / denominator // bytes per hour
        if slope > stableBytesPerHour { return RunwayEstimate(state: .growing(bytesPerHour: slope), free: free, basedOn: span) }
        if slope >= -stableBytesPerHour { return RunwayEstimate(state: .stable, free: free, basedOn: span) }
        let burn = -slope, days = latest.free / burn / 24
        if days > horizonDays { return RunwayEstimate(state: .stable, free: free, basedOn: span) }
        let five = max(0, (latest.free - 5e9) / burn / 24)
        return RunwayEstimate(state: .shrinking(bytesPerHour: burn, daysToFull: days, daysToFiveGB: five), free: free, basedOn: span)
    }
}

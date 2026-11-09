import Foundation

public struct LeakFinding: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var members: Int
    public var current: UInt64
    public var growth: UInt64
    public var span: Double
    public var slopePerHour: Double
    public var explanation: String {
        let minutes = max(1, Int((span / 60).rounded()))
        return "\(title) has grown \(MetricFormat.bytes(growth)) in \(minutes) min (about \(MetricFormat.bytes(UInt64(max(0, slopePerHour))))/hour) and is still climbing. Memory that only goes up can be a leak; quitting and reopening it usually gives the memory back."
    }
}
/// Flags owners whose summed resident memory climbs steadily. In memory only; bounded per owner.
public struct LeakWatch: Sendable {
    public struct Policy: Sendable {
        public var window = 1800.0, minimumSpan = 600.0, spacing = 20.0, resetGap = 120.0
        public var minimumGrowth = 50_000_000.0, minimumSlopePerHour = 100_000_000.0
        public var minimumFit = 0.85, minimumRise = 0.8
        public init() {}
    }
    public struct Item: Sendable {
        public var id: String, title: String, members: Int, bytes: UInt64
        public init(id: String, title: String, members: Int, bytes: UInt64) { self.id = id; self.title = title; self.members = members; self.bytes = bytes }
    }
    private struct Series: Sendable { var title: String; var members: Int; var lastSeen: Double; var points: [(time: Double, bytes: Double)] }
    public let policy: Policy
    private var series: [String: Series] = [:]
    private var lastTime: Double?
    public init(policy: Policy = Policy()) { self.policy = policy }
    public var trackedCount: Int { series.count }
    public var historySpan: Double { series.values.compactMap { s in s.points.last.map { $0.time } .flatMap { end in s.points.first.map { end - $0.time } } }.max() ?? 0 }
    public mutating func record(_ items: [Item], at time: Double) {
        if let lastTime {
            if time <= lastTime { return }
            if time - lastTime > policy.resetGap { series.removeAll(keepingCapacity: true) }
            else if time - lastTime < policy.spacing { return }
        }
        lastTime = time
        // An owner may miss a reading (a transient unreadable process); only a long absence ends its history.
        series = series.filter { time - $0.value.lastSeen <= policy.resetGap }
        for item in items {
            var entry = series[item.id] ?? Series(title: item.title, members: item.members, lastSeen: time, points: [])
            entry.title = item.title; entry.members = item.members; entry.lastSeen = time
            entry.points.append((time, Double(item.bytes)))
            if let cut = entry.points.firstIndex(where: { $0.time >= time - policy.window }), cut > 0 { entry.points.removeFirst(cut) }
            series[item.id] = entry
        }
    }
    public func findings() -> [LeakFinding] {
        series.compactMap { id, entry in evaluate(id, entry) }.sorted { $0.slopePerHour == $1.slopePerHour ? $0.id < $1.id : $0.slopePerHour > $1.slopePerHour }
    }
    private func evaluate(_ id: String, _ entry: Series) -> LeakFinding? {
        let points = entry.points
        guard let first = points.first, let last = points.last, points.count >= 8 else { return nil }
        let span = last.time - first.time
        guard span >= policy.minimumSpan, last.bytes - first.bytes >= policy.minimumGrowth else { return nil }
        let peak = points.map(\.bytes).max() ?? 0
        guard last.bytes >= peak * 0.95 else { return nil } // still climbing, not a spike that came back down
        var rises = 0
        for (a, b) in zip(points, points.dropFirst()) where b.bytes - a.bytes >= -max(1_000_000, a.bytes * 0.005) { rises += 1 }
        guard Double(rises) / Double(points.count - 1) >= policy.minimumRise else { return nil }
        let n = Double(points.count)
        let xs = points.map { ($0.time - first.time) / 3600 }, ys = points.map(\.bytes)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        let syy = ys.reduce(0) { $0 + ($1 - meanY) * ($1 - meanY) }
        guard sxx > 0, syy > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let slope = sxy / sxx, fit = sxy * sxy / (sxx * syy)
        guard slope >= policy.minimumSlopePerHour, fit >= policy.minimumFit else { return nil }
        return LeakFinding(id: id, title: entry.title, members: entry.members, current: UInt64(last.bytes), growth: UInt64(last.bytes - first.bytes), span: span, slopePerHour: slope)
    }
}

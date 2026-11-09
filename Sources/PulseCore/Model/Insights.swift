import Foundation

/// Everything the v7 views draw, prepared on the sampling queue and published only while a window is open.
public struct Insights: Sendable, Equatable {
    public var timeline: [TimelineSample] = []
    public var events: [ThermalEvent] = []
    public var leaks: [LeakFinding] = []
    public var leakTracked = 0
    public var leakHistory = 0.0
    public var runway = RunwayEstimate()
    public var startedAt: Double?
    public init() {}
    public init(timeline: [TimelineSample], events: [ThermalEvent], leaks: [LeakFinding], leakTracked: Int, leakHistory: Double, runway: RunwayEstimate, startedAt: Double?) {
        self.timeline = timeline; self.events = events; self.leaks = leaks; self.leakTracked = leakTracked
        self.leakHistory = leakHistory; self.runway = runway; self.startedAt = startedAt
    }
}

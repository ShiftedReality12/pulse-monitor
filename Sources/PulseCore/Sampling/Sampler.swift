import Foundation

/// Serial-queue-owned sampler; the GUI and headless benchmark share this real producer.
public final class Sampler: @unchecked Sendable {
    private let system: SystemSampler
    private let processes: ProcessSampler
    private var cachedProcesses = Snapshot()
    private var lastProcessTime: TimeInterval?
    private var verdict = VerdictTracker()
    private var ranking = ImpactRanking()
    private var ownerHistory = OwnerHistory()
    private var wasVisible = false
    public convenience init(baselineURL: URL? = nil) { self.init(baselineURL: baselineURL, processes: ProcessSampler()) }
    init(baselineURL: URL? = nil, processes: ProcessSampler) {
        system = SystemSampler(baselineURL: baselineURL); self.processes = processes
    }
    public func sample(includeProcesses visible: Bool = true, forceProcessRefresh: Bool = false, uptime: TimeInterval? = nil) -> Snapshot {
        var snapshot = system.sample()
        let now = uptime ?? ProcessInfo.processInfo.systemUptime
        defer { wasVisible = visible }
        let opening = visible && !wasVisible
        if opening || forceProcessRefresh || lastProcessTime.map({ now - $0 >= SamplingPolicy.processInterval(visible: visible) }) ?? true {
            processes.collect(into: &snapshot, now: now)
            snapshot.groups = ranking.rank(snapshot.groups, totalMemory: snapshot.memoryTotal ?? 0, cores: ProcessInfo.processInfo.processorCount, uptime: now)
            ownerHistory.apply(to: &snapshot.groups)
            cachedProcesses = snapshot; lastProcessTime = now
        } else {
            snapshot.groups = cachedProcesses.groups; snapshot.processCount = cachedProcesses.processCount
            snapshot.limitedProcessCount = cachedProcesses.limitedProcessCount; snapshot.topMemoryGroup = cachedProcesses.topMemoryGroup
            snapshot.processSampleDate = cachedProcesses.processSampleDate
        }
        verdict.apply(to: &snapshot, uptime: now)
        return snapshot
    }
}

public final class SamplingSession: @unchecked Sendable {
    private let sampler = Sampler()
    private var timeline = TimelineStore()
    private var leaks = LeakWatch()
    private var leakFindings: [LeakFinding] = []
    private var lastOwnerSample: Date?
    private var startedAt: Double?
    private var demoTimelineSeeded = false
    public private(set) var history = NumericHistory()
    /// Refreshed on every visible sample; read on the same queue right after `sample`.
    public private(set) var insights = Insights()
    public init() {}
    public func sample(visible: Bool, forceProcessRefresh: Bool = false) -> (Snapshot, PlotHistory?) {
        if !demoTimelineSeeded && PulseEnvironment.demoEnabled() {
            demoTimelineSeeded = true
            let seed = DemoData.timelineSeed()
            timeline.preload(seed)
            startedAt = seed.first?.time
        }
        let snapshot = sampler.sample(includeProcesses: visible, forceProcessRefresh: forceProcessRefresh)
        history.append(HistorySample(snapshot))
        let time = snapshot.date.timeIntervalSince1970
        startedAt = startedAt ?? time
        timeline.record(time: time, pressure: snapshot.pressure.level, swap: snapshot.swap, compressed: snapshot.compressed, diskFree: snapshot.diskFree,
                        thermal: TimelineSample.thermalLevel(snapshot.thermal), speedLimit: snapshot.cpuSpeedLimit)
        if let date = snapshot.processSampleDate, date != lastOwnerSample {
            lastOwnerSample = date
            leaks.record(snapshot.groups.compactMap { group in
                group.resident.map { LeakWatch.Item(id: group.id, title: HumanCopy.ownerName(group), members: group.members.count, bytes: $0) }
            }, at: date.timeIntervalSince1970)
            leakFindings = leaks.findings()
        }
        if visible {
            let samples = timeline.samples
            insights = Insights(timeline: samples, events: timeline.events, leaks: leakFindings, leakTracked: leaks.trackedCount, leakHistory: leaks.historySpan,
                                runway: DiskRunway.estimate(samples: samples, now: time), startedAt: startedAt)
        }
        return (snapshot, visible ? PlotHistory(history) : nil)
    }
}

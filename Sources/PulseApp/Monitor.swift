import Observation
import SwiftUI
import PulseCore

@MainActor @Observable
final class Monitor {
    static let shared = Monitor()
    /// Stored off the observation graph. SwiftUI refreshes from `renderToken` only when the drawn text changes.
    @ObservationIgnored var snapshot = Snapshot() { didSet { verdict = HumanCopy(snapshot) } }
    @ObservationIgnored private(set) var verdict = HumanCopy(Snapshot())
    let disk = DiskUsageModel()
    let drilldown = ProcessDrilldownModel()
    let usage = UsageModel()
    @ObservationIgnored private(set) var insights = Insights()
    private(set) var providers = ProviderRegistry.standard()
    @ObservationIgnored var plots = PlotHistory()
    func hasProvider(_ id: String) -> Bool { providers.available.contains { $0.id == id } }
    var menuText = "—"
    var menuWarning = false
    var menuVerdict = "Collecting readings"
    /// Bumped only when a visible window would draw something new. Views must read it.
    private(set) var paint = 0
    var renderToken: Int { paint }
    private var surfaces: Set<String> = []
    private var applicationShown = true
    private var isVisible: Bool { applicationShown && !surfaces.isEmpty }
    private var screenToken = ""
    private var forcePaint = true
    private let mailbox = Mailbox()
    private let queue = DispatchQueue(label: "com.pulse.sample", qos: .utility, autoreleaseFrequency: .workItem)
    private let session = SamplingSession()
    private var timer: DispatchSourceTimer?
    /// Tests advance this clock. Production uses system uptime, and the registry still waits 900 seconds.
    var providerTime: @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }
    init() { providers.refresh(); schedule() }
    func visibility(_ id: String, shown: Bool) {
        let wasVisible = isVisible
        if shown { forcePaint = true }
        if shown {
            if surfaces.insert(id).inserted && applicationShown {
                disk.windowOpened()
                queue.async(execute: Self.handler(session: session, mailbox: mailbox, monitor: self, visible: true, forceProcessRefresh: true))
            }
        } else { surfaces.remove(id) }
        disk.update(visible: isVisible, fullWindow: applicationShown && surfaces.contains("window"), sessions: snapshot.groups)
        if wasVisible != isVisible { schedule() }
    }
    func applicationVisibility(_ shown: Bool) {
        let wasVisible = isVisible
        applicationShown = shown
        if shown { forcePaint = true }
        disk.update(visible: isVisible, fullWindow: applicationShown && surfaces.contains("window"), sessions: snapshot.groups)
        if wasVisible != isVisible {
            if isVisible { queue.async(execute: Self.handler(session: session, mailbox: mailbox, monitor: self, visible: true, forceProcessRefresh: true)) }
            schedule()
        }
    }
    func stopSampling() { timer?.cancel(); timer = nil; disk.update(visible: false, sessions: []) }
    private func schedule() {
        timer?.cancel()
        let visible = isVisible
        let mailbox = mailbox
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + (visible ? SamplingPolicy.interval(visible: true) : 0), repeating: SamplingPolicy.interval(visible: visible), leeway: .milliseconds(Int(SamplingPolicy.leeway(visible: visible) * 1000)))
        source.setEventHandler(handler: Self.handler(session: session, mailbox: mailbox, monitor: self, visible: visible))
        source.resume(); timer = source
    }
    func apply(_ batch: Mailbox.Batch) {
        providers.refresh(at: providerTime())
        let snapshot = batch.snapshot
        if let date = snapshot.processSampleDate, date != self.snapshot.processSampleDate { RenderDiagnostics.shared.record("process.refresh") }
        let readingsChanged = !self.snapshot.hasSameReadings(as: snapshot)
        self.snapshot = snapshot
        if readingsChanged { RenderDiagnostics.shared.record("snapshot.publish") }
        if isVisible && drilldown.isOpen { drilldown.record(groups: snapshot.groups, sampledAt: snapshot.processSampleDate) }
        disk.update(visible: isVisible, fullWindow: applicationShown && surfaces.contains("window"), sessions: snapshot.groups)
        if let plots = batch.plots { self.plots = plots }
        if let insights = batch.insights { self.insights = insights }
        if surfaces.contains("window") && applicationShown {
            usage.refreshIfDue(provider: providers.available.first { $0.id == "usage-strip" } as? UsageStripProvider)
        }
        let menu = MetricFormat.percent(snapshot.memoryPercent)
        if menuText != menu { menuText = menu }
        if menuWarning != snapshot.needsAttention { menuWarning = snapshot.needsAttention }
        if menuVerdict != verdict.headline { menuVerdict = verdict.headline }
        let token = ScreenSignature.token(snapshot: snapshot, plots: plots, insights: insights)
        if isVisible && (forcePaint || token != screenToken) {
            screenToken = token
            forcePaint = false
            paint += 1
        }
        RenderDiagnostics.shared.publishIfRequested()
    }
    nonisolated private static func handler(session: SamplingSession, mailbox: Mailbox, monitor: Monitor, visible: Bool, forceProcessRefresh: Bool = false) -> @Sendable () -> Void {
        { [weak monitor] in
            RenderDiagnostics.shared.record("sample.tick")
            let batch = autoreleasepool { () -> Mailbox.Batch in
                let (snapshot, plots) = session.sample(visible: visible, forceProcessRefresh: forceProcessRefresh)
                return Mailbox.Batch(snapshot: snapshot, plots: plots, insights: visible ? session.insights : nil)
            }
            guard mailbox.enqueue(batch) else { return }
            Task { @MainActor [weak monitor] in
                guard let monitor else { return }
                while let next = mailbox.take() { monitor.apply(next) }
            }
        }
    }
}

/// One pending main-actor publish. A slow frame keeps the newest sample and drops the ones in between.
final class Mailbox: @unchecked Sendable {
    struct Batch {
        var snapshot: Snapshot
        var plots: PlotHistory?
        var insights: Insights?
    }
    private let lock = NSLock()
    private var latest: Batch?
    private var scheduled = false
    func enqueue(_ batch: Batch) -> Bool {
        lock.lock(); defer { lock.unlock() }
        latest = batch
        if scheduled { return false }
        scheduled = true
        return true
    }
    func take() -> Batch? {
        lock.lock(); defer { lock.unlock() }
        let batch = latest
        latest = nil
        if batch == nil { scheduled = false }
        return batch
    }
}

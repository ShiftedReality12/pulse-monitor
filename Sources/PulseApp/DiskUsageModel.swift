import Foundation
import Observation
import PulseCore

/// Window-lifetime loading: redraws never own or cancel the shared measurement.
@MainActor @Observable final class DiskUsageModel {
    private(set) var estimates: [DiskEstimate] = []
    private(set) var loading = false
    private(set) var fullDiskAccess = false
    var accessHint: String { fullDiskAccess ? "Unmeasured includes APFS use and unfinished folders." : "Give Pulse Full Disk Access to see inside" }
    private let cpuSample: @MainActor () -> Double
    private let service: DiskEstimates
    init(service: DiskEstimates = .shared, cpuSample: @escaping @MainActor () -> Double = { Benchmark.cpu(Benchmark.usage()) }) { self.service = service; self.cpuSample = cpuSample }
    private var task: Task<Void, Never>?
    private var requested: [String] = []
    private var completed: [String] = []
    private var lastPublish = Date.distantPast
    private var measuredAt = Date.distantPast
    private var visible = false
    private var fullWindow = false
    private var duty = DiskScanDuty()
    private var needsAccessRefresh = true
    private var openedAt = ProcessInfo.processInfo.systemUptime
    func windowOpened() { needsAccessRefresh = true; measuredAt = .distantPast }
    func update(visible: Bool, fullWindow: Bool = true, sessions: [ProcessGroup]) {
        if visible && !self.visible { openedAt = ProcessInfo.processInfo.systemUptime; needsAccessRefresh = true }
        let windowVisible = visible && fullWindow
        if windowVisible && !self.fullWindow { duty.reset(wall: ProcessInfo.processInfo.systemUptime, cpu: cpuSample()) }
        self.fullWindow = windowVisible
        self.visible = visible
        guard visible else { task?.cancel(); return }
        requested = DiskBreakdown.projectPaths(sessions).sorted()
        loadIfNeeded()
    }
    /// Bytes, status and the clock minute. A newer timestamp in the same minute is not a new drawing.
    nonisolated static func displayToken(_ items: [DiskEstimate]) -> [String] {
        items.map { "\($0.path)\t\(MetricFormat.bytes($0.bytes))\t\($0.complete)\t\($0.stale)\t\($0.status)\t\(Int($0.date.timeIntervalSince1970 / 60))" }
    }
    private func loadIfNeeded() {
        guard visible, task == nil,
              needsAccessRefresh || requested != completed || Date().timeIntervalSince(measuredAt) >= 300 else { return }
        let roots = requested, service = service
        loading = loading || estimates.isEmpty
        task = Task(priority: .utility) { [weak self] in
            if self?.needsAccessRefresh == true {
                _ = await service.refreshAccess(); self?.needsAccessRefresh = false
            }
            if self?.estimates.isEmpty == true {
                let cached = await service.cachedEstimates().filter { $0.complete || ($0.bytes ?? 0) > 0 }
                if !Task.isCancelled, !cached.isEmpty, let self {
                    estimates = cached
                    if roots.isEmpty || roots.allSatisfy({ path in cached.contains { $0.path == path } }) { loading = false }
                }
            }
            guard let self else { return }
            guard fullWindow else { loading = false; task = nil; return }
            let allowance = duty.allowance(wall: ProcessInfo.processInfo.systemUptime, cpu: cpuSample(), fullWindow: true)
            if allowance < 0.0005 {
                try? await Task.sleep(for: .milliseconds(200)); task = nil; loadIfNeeded(); return
            }
            let result = await service.load(additionalRoots: roots.map { URL(fileURLWithPath: $0, isDirectory: true) }, seconds: 0.3, cpuSeconds: allowance)
            let granted = await service.fullDiskAccessGranted(), pending = await service.hasPendingWork()
            if !Task.isCancelled {
                if fullDiskAccess != granted { fullDiskAccess = granted }
                if loading || !pending || Date().timeIntervalSince(lastPublish) >= 2 {
                    let next = result.filter { $0.complete || ($0.bytes ?? 0) > 0 }
                    // `date` changes every slice. Publishing that redraws the window when the caption does not.
                    if Self.displayToken(next) != Self.displayToken(estimates) { estimates = next }
                    lastPublish = Date()
                }
                completed = roots; measuredAt = Date()
                if pending {
                    measuredAt = .distantPast
                }
                RenderDiagnostics.shared.record("disk.completed")
                RenderDiagnostics.shared.captureDiskLoad(seconds: ProcessInfo.processInfo.systemUptime - openedAt)
            }
            if loading {
                let missing = roots.isEmpty ? estimates.isEmpty : roots.contains { path in !estimates.contains { $0.path == path } }
                loading = missing && measuredAt == .distantPast && !Task.isCancelled
            }
            if !Task.isCancelled, visible, measuredAt == .distantPast {
                try? await Task.sleep(for: .milliseconds(200))
            }
            task = nil
            loadIfNeeded()
        }
    }
}

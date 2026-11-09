import Foundation

/// FIFO utility queue owns every cursor and syscall; actor callers may safely interleave awaits.
public actor DiskEstimates {
    public static let shared = DiskEstimates()
    public static var defaultRoots: [URL] { DiskScanWorker.defaultRoots }
    private let queue = DispatchQueue(label: "local.pulse.disk", qos: .utility)
    private var checkpointScheduled = false
    private let worker: DiskScanWorker
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                probe: @escaping @Sendable () -> Bool = { FullDiskAccess.granted() },
                observer: @escaping @Sendable (String) -> Void = { _ in },
                cacheURL: URL? = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Pulse/disk-cache.json"),
                now: @escaping @Sendable () -> Date = { Date() }) {
        worker = DiskScanWorker(home: home, probe: probe, observer: observer, cacheURL: cacheURL, now: now)
    }
    private func perform<T: Sendable>(_ action: @escaping @Sendable (DiskScanWorker, ScanCancellation) -> T) async -> T {
        let worker = worker, cancellation = ScanCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: action(worker, cancellation)) }
            }
        } onCancel: { cancellation.cancel() }
    }
    public func refreshAccess() async -> Bool { await perform { worker, _ in worker.refreshAccess() } }
    public func fullDiskAccessGranted() async -> Bool { await perform { worker, _ in worker.fullDiskAccessGranted() } }
    public func cachedEstimates() async -> [DiskEstimate] { await perform { worker, _ in worker.cachedEstimates() } }
    public func scanEntries() async -> [String: Int] { await perform { worker, _ in worker.scanEntries() } }
    public func openDirectoryCount() async -> Int { await perform { worker, _ in worker.discovery.openDescriptors + worker.cursors.values.reduce(0) { $0 + $1.openDescriptors } } }
    public func hasInitialWork() async -> Bool { await perform { worker, _ in worker.initialPending } }
    public func hasPendingWork() async -> Bool { await perform { worker, _ in worker.pending } }
    public func load(roots: [URL]? = nil, additionalRoots: [URL] = [], limit: Int = 200_000, seconds: Double = 3, cpuSeconds: Double? = nil) async -> [DiskEstimate] {
        guard !Task.isCancelled else { return [] }
        let result = await perform { worker, cancellation in worker.load(roots: roots, additionalRoots: additionalRoots, limit: limit, seconds: seconds, cancellation: cancellation, cpuSeconds: cpuSeconds) }
        if !checkpointScheduled, let delay = await perform({ worker, _ in worker.store.url == nil ? nil : worker.store.writeDelay }), delay > 0 {
            checkpointScheduled = true
            let worker = worker
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                worker.checkpoint()
                Task { await self?.checkpointFinished() }
            }
        }
        return result
    }
    private func checkpointFinished() { checkpointScheduled = false }
    public static func measure(root: URL, limit: Int = 200_000, seconds: Double = 3) -> DiskEstimate {
        var walker = DiskWalker(policy: .shared, budget: DiskScanBudget(limit: limit, seconds: seconds))
        return walker.measure(root)
    }
}

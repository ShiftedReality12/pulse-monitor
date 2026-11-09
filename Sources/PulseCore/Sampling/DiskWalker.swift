import Foundation
import Darwin

/// One monotonic budget for the entire pass, including all roots and metadata work.
final class DiskScanBudget {
    let cancellation: ScanCancellation?
    private let clock: () -> Double
    private let cpuDeadline: Double
    private let deadline: Double
    private let limit: Int
    private(set) var entries = 0
    init(limit: Int = 200_000, seconds: Double = 3,
         clock: @escaping () -> Double = { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9 }, cancellation: ScanCancellation? = nil, cpuSeconds: Double? = nil) {
        cpuDeadline = cpuSeconds.map { Self.threadCPU + max(0, $0) } ?? .infinity
        self.cancellation = cancellation
        self.clock = clock; self.limit = min(200_000, max(0, limit))
        deadline = clock() + min(3, max(0, seconds))
    }
    var available: Bool { cancellation?.cancelled != true && !Task.isCancelled && entries < limit && clock() < deadline && (!cpuDeadline.isFinite || Self.threadCPU < cpuDeadline) }
    static var threadCPU: Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9 }
    var nativeCPUDeadline: Double { cpuDeadline.isFinite ? cpuDeadline : 0 }
    var remaining: Int { max(0, limit - entries) }
    func charge(_ count: Int) { entries += min(remaining, count) }
    func take() -> Bool {
        guard available else { return false }
        entries += 1; return true
    }
}
struct DiskWalker {
    let policy: ProtectedPaths
    let budget: DiskScanBudget
    mutating func measure(_ root: URL) -> DiskEstimate {
        let omitted = DiskRootPlan.omitted(home: FileManager.default.homeDirectoryForCurrentUser)
        if DiskRootPlan.isOmitted(root.path, home: FileManager.default.homeDirectoryForCurrentUser) { return DiskEstimate(path: root.path, bytes: nil, complete: false, date: Date()) }
        let cursor = DiskScanCursor()
        let result = cursor.advance(path: ProtectedPaths.normalized(root.path), policy: policy,
                                    budget: budget, slice: budget, excluding: omitted)
        return DiskEstimate(path: result.path, bytes: result.bytes.map { $0 + cursor.nodeBytes },
                            complete: result.complete, date: result.date)
    }
}

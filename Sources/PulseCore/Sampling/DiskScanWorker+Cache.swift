import Foundation
import Darwin

extension DiskScanWorker {
    func refreshAccess() -> Bool {
        let result = probe()
        if access != result { access = result; discovered = nil; installedRoots = nil; discovery = DiskRootDiscovery() }
        let policy = ProtectedPaths(home: home.path, fullDiskAccess: result)
        for path in cursors.keys where !policy.allows(path) { cursors[path] = nil; cache[path] = nil; completed[path] = nil; completedNodes[path] = nil }
        return result
    }
    func cachedEstimates() -> [DiskEstimate] {
        let granted = fullDiskAccessGranted()
        if let restoredAccess, restoredAccess != granted { cache = [:]; cursors = [:]; lastExclusions = [] }
        restoredAccess = nil
        let policy = ProtectedPaths(home: home.path, fullDiskAccess: granted)
        var result = cache.values.filter { policy.allows($0.path) && !DiskRootPlan.isOmitted($0.path, home: home) && !DiskRootPlan.isTestFixture($0.path) }
        let nodes = cursors.filter { policy.allows($0.key) }.reduce(UInt64(0)) { $0 + (completedNodes[$1.key] ?? $1.value.nodeBytes) }
        if nodes > 0 { result.append(DiskEstimate(path: DiskRootPlan.nodes, bytes: nodes, complete: result.allSatisfy(\.complete), date: result.map(\.date).max() ?? Date(), partitioned: true)) }
        return result.sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
    }
    func scanEntries() -> [String: Int] { cursors.mapValues { $0.entries } }
    func fullDiskAccessGranted() -> Bool {
        if let access { return access }
        let result = probe(); access = result; return result
    }
    func reusable(path: String, cached: DiskEstimate, policy: ProtectedPaths, budget: DiskScanBudget) -> Bool {
        guard now().timeIntervalSince(cached.date) < 300 else { return false }
        guard let signature = cursors[path]?.rootSignature else { return true } // Legacy snapshot, bounded by TTL.
        guard let fd = policy.openDirectory(path, budget: budget) else { return false }
        defer { close(fd) }
        return DiskDirectory.signature(fd) == signature
    }
    func checkpoint() {
        guard let url = store.url, FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else { return }
        store.write(DiskCacheSnapshot(home: home.path, granted: access ?? false, exclusions: lastExclusions,
                                     cursors: cursors.mapValues { $0.state }, completed: completed, estimates: cache, completedNodes: completedNodes))
    }
}

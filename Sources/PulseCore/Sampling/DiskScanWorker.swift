import Foundation
import Darwin

/// Visible consumers only. Fair resumable slices share a <=3s / <=200k-entry pass.
final class DiskScanWorker: @unchecked Sendable {
    var cache: [String: DiskEstimate] = [:]
    var cursors: [String: DiskScanCursor] = [:]
    let home: URL
    let homeDevice: Int64?
    let probe: @Sendable () -> Bool
    let observer: @Sendable (String) -> Void
    var access: Bool?
    var discovered: [URL]?
    var installedRoots: [URL]?
    let configuredRoots: [URL]
    var lastExclusions: Set<String> = []
    var rotation = 0
    var residentRoot: String?
    var store: DiskCacheStore
    var restoredAccess: Bool?
    var pending = false
    var initialPending = true
    let now: @Sendable () -> Date
    var completed: [String: DiskEstimate] = [:]
    var completedNodes: [String: UInt64] = [:]
    var discovery = DiskRootDiscovery()
    var installedAt = Date.distantPast
    var discoveredAt = Date.distantPast
    func hasPendingWork() -> Bool { pending }
    func dropTestFixtures() {
        cache = cache.filter { !DiskRootPlan.isTestFixture($0.key) }
        cursors = cursors.filter { !DiskRootPlan.isTestFixture($0.key) }
        completed = completed.filter { !DiskRootPlan.isTestFixture($0.key) }
        completedNodes = completedNodes.filter { !DiskRootPlan.isTestFixture($0.key) }
    }
    static let defaultRoots: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let policy = ProtectedPaths(home: home.path), budget = DiskScanBudget()
        return Array(Set(DiskRootPlan.defaults(home: home, policy: policy, budget: budget) + DiskRootPlan.discover(home: home, policy: policy, budget: budget)))
    }()
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                probe: @escaping @Sendable () -> Bool = { FullDiskAccess.granted() },
                observer: @escaping @Sendable (String) -> Void = { _ in },
                cacheURL: URL? = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Pulse/disk-cache.json"),
                now: @escaping @Sendable () -> Date = { Date() }) {
        var info = stat(); homeDevice = stat(home.path, &info) == 0 ? Int64(info.st_dev) : nil
        self.now = now
        configuredRoots = DiskConfiguration.roots(home: home)
        self.home = home; self.probe = probe; self.observer = observer
        store = DiskCacheStore(url: cacheURL == DiskCacheStore.defaultURL && home != FileManager.default.homeDirectoryForCurrentUser ? nil : cacheURL)
        if let saved = store.read(home: home.path) {
            lastExclusions = saved.exclusions; restoredAccess = saved.granted
            cursors = saved.cursors.mapValues { DiskScanCursor(state: $0) }
            completed = saved.completed ?? [:]; completedNodes = saved.completedNodes ?? [:]
            cache = Dictionary(uniqueKeysWithValues: saved.cursors.map { path, state in
                (path, DiskEstimate(path: path, bytes: state.bytes, complete: state.finished && !state.failed, date: state.date, partitioned: true))
            })
            if let estimates = saved.estimates { cache = estimates }
            for (path, old) in completed where cache[path]?.complete != true { var stale = old; stale.stale = true; cache[path] = stale }
            dropTestFixtures()
        }
    }
    func load(roots: [URL]? = nil, additionalRoots: [URL] = [], limit: Int = 200_000, seconds: Double = 3, cancellation: ScanCancellation? = nil, cpuSeconds: Double? = nil) -> [DiskEstimate] {
        guard cancellation?.cancelled != true else { return [] }
        _ = refreshAccess()
        _ = cachedEstimates()
        let granted = fullDiskAccessGranted(), budget = DiskScanBudget(limit: limit, seconds: seconds, cancellation: cancellation, cpuSeconds: cpuSeconds)
        let policy = ProtectedPaths(home: home.path, fullDiskAccess: granted, observer: observer)
        let automatic = roots == nil
        if automatic && (discovered == nil || now().timeIntervalSince(discoveredAt) >= 300) {
            if discovery.homeComplete { discovery.resetHome() }
            let found = discovery.scanHome(home: home, policy: policy, budget: budget)
            discovered = Array(Set((discovered ?? []) + found.roots))
            if found.complete { discovered = found.roots; discoveredAt = now() }
        }
        if automatic && (installedRoots == nil || now().timeIntervalSince(installedAt) >= 300) {
            if discovery.defaultsComplete { discovery.resetDefaults() }
            let found = discovery.scanDefaults(home: home, policy: policy, budget: budget)
            installedRoots = Array(Set((installedRoots ?? []) + found.roots))
            if found.complete { installedRoots = found.roots; installedAt = now() }
        }
        var paths = Set((roots ?? ((installedRoots ?? []) + (discovered ?? []) + configuredRoots + additionalRoots)).map { ProtectedPaths.normalized($0.path) })
        if automatic && granted {
            for name in ["Music", "Pictures", "Movies", "Library", "Desktop", "Documents", "Downloads"] {
                paths.insert(home.appendingPathComponent(name).path)
            }
        }
        paths = Set(paths.filter { !DiskRootPlan.isOmitted($0, home: home) })
        let dockerPath = home.appendingPathComponent(DiskRootPlan.docker).path
        let exclusions = paths.union([dockerPath]).union(DiskRootPlan.omitted(home: home))
        // A changed partition invalidates overlapping totals; never double-count old cached ownership.
        let changed = exclusions.symmetricDifference(lastExclusions)
        for path in Set(cursors.keys).union(cache.keys) where changed.contains(where: { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }) {
            cursors[path] = nil; cache[path] = nil; completed[path] = nil; completedNodes[path] = nil
        }
        lastExclusions = exclusions
        let ordered = paths.sorted()
        let active = ordered.filter { policy.allows($0) }
        let unfinished = active.filter { path in
            guard let cached = cache[path], cursors[path]?.finished == true else { return true }
            return !reusable(path: path, cached: cached, policy: policy, budget: budget)
        }
        let projects = Set(additionalRoots.map { ProtectedPaths.normalized($0.path) })
        let ancestors = Set(unfinished.filter { path in projects.contains { $0.hasPrefix(path + "/") } })
        let priority = ancestors.isEmpty ? projects : ancestors
        let first = unfinished.filter { priority.contains($0) }
        let rest = unfinished.filter { !priority.contains($0) }
        let rotated = rest.isEmpty ? rest : Array(rest[(rotation % rest.count)...] + rest[..<(rotation % rest.count)])
        let work = first + rotated
        let count = max(1, work.count)
        for index in 0..<work.count {
            guard budget.available else { break }
            let path = work[index]
            let prioritized = !first.isEmpty && !rest.isEmpty
            let share = prioritized ? (index < first.count ? 0.9 : 0.1) : 1.0
            let peers = max(1, prioritized ? (index < first.count ? first.count : rest.count) : count)
            let quota = max(1, Int(Double(min(200_000, max(0, limit))) * share) / peers)
            let time = min(3, max(0, seconds)) * share / Double(peers)
            if cursors[path]?.finished == true { cursors[path] = DiskScanCursor(emptyDirectories: cursors[path]?.emptyDirectories ?? [:]) }
            if residentRoot != path { if let old = residentRoot { cursors[old]?.suspend() }; residentRoot = path }
            let cursor = cursors[path] ?? DiskScanCursor(); cursors[path] = cursor
            let result = cursor.advance(path: path, policy: policy, budget: budget,
                                        slice: DiskScanBudget(limit: quota, seconds: time, cancellation: cancellation), excluding: exclusions, expectedDevice: homeDevice, keepOpen: true)
            let estimate = DiskEstimate(path: path, bytes: result.bytes, complete: result.complete, date: now(), partitioned: true, skippedDirectories: result.skippedDirectories)
            if result.complete { completed[path] = estimate; completedNodes[path] = cursor.nodeBytes }
            if let previous = completed[path], !result.complete { var stale = previous; stale.stale = true; cache[path] = stale }
            else { cache[path] = estimate }
        }
        rotation = (rotation + 1) % count
        var result = ordered.map { path in
            policy.allows(path) ? cache[path] ?? DiskEstimate(path: path, bytes: nil, complete: false, date: Date())
                : DiskEstimate(path: path, bytes: nil, complete: false, date: Date())
        }
        let nodes = active.reduce(UInt64(0)) { $0 + (completedNodes[$1] ?? cursors[$1]?.nodeBytes ?? 0) }
        if nodes > 0 { result.append(DiskEstimate(path: DiskRootPlan.nodes, bytes: nodes,
                                                 complete: active.allSatisfy { cache[$0]?.complete == true },
                                                 date: active.compactMap { cache[$0]?.date }.max() ?? Date(), partitioned: true)) }
        if automatic && granted { result.append(DiskRootPlan.dockerSize(home: home, policy: policy, budget: budget)) }
        let planning = automatic && (!discovery.homeComplete || !discovery.defaultsComplete)
        initialPending = planning || active.contains { completed[$0] == nil && (cursors[$0] == nil || cursors[$0]?.finished == false) }
        pending = planning || active.contains { cursors[$0] == nil || cursors[$0]?.finished == false }
        store.write(DiskCacheSnapshot(home: home.path, granted: granted, exclusions: exclusions, cursors: cursors.mapValues { $0.state }, completed: completed, estimates: cache, completedNodes: completedNodes))
        return result.sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
    }
}

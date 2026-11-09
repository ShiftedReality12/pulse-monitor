import Foundation
import Darwin
import Testing
@testable import PulseCore

private final class DiskTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var offset: Double = 0
    func advance(_ seconds: Double) { lock.lock(); offset += seconds; lock.unlock() }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return Date().addingTimeInterval(offset) }
}
@Test func completedTotalsAndNodesSurviveTTLRefreshAndUnrelatedPartitionChanges() async throws {
    let home = try disk59Fixture(), clock = DiskTestClock()
    defer { try? FileManager.default.removeItem(at: home) }
    let dev = home.appendingPathComponent("dev"), other = home.appendingPathComponent("other"), project = dev.appendingPathComponent("project")
    for index in 0..<30 { try disk59File(dev.appendingPathComponent("file\(index)")) }
    try disk59File(dev.appendingPathComponent("node_modules/package/data"))
    try disk59File(project.appendingPathComponent("data")); try disk59File(other.appendingPathComponent("data"))
    let service = DiskEstimates(home: home, probe: { false }, cacheURL: nil, now: { clock.now() })
    let original = await service.load(roots: [dev, other])
    let otherValue = try #require(original.first { $0.path == other.path })
    let changed = await service.load(roots: [dev, other, project], limit: 3)
    #expect(changed.first { $0.path == other.path } == otherValue)
    _ = await service.load(roots: [dev, other, project])
    let finished = await service.load(roots: [dev, other, project])
    clock.advance(301)
    let refresh = await service.load(roots: [dev, other, project], limit: 3)
    for old in finished where old.complete {
        let current = try #require(refresh.first { $0.path == old.path })
        #expect(current.complete && current.bytes == old.bytes)
    }
    #expect(refresh.contains { $0.stale })
}
@Test func suspendedCursorKeepsNoDescriptorsAndSymlinksRemainComplete() throws {
    let home = try disk59Fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let deep = home.appendingPathComponent("a/b/c/d")
    try disk59File(deep.appendingPathComponent("data"))
    try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("alias"), withDestinationURL: deep)
    let cursor = DiskScanCursor()
    let policy = ProtectedPaths(home: home.path)
    for _ in 0..<20 {
        _ = cursor.advance(path: home.path, policy: policy, budget: DiskScanBudget(limit: 2), slice: DiskScanBudget(limit: 2), excluding: [])
        #expect(cursor.openDescriptors == 0)
        if cursor.finished { break }
    }
    #expect(cursor.finished && cursor.bytes != nil)
    #expect(cursor.advance(path: home.path, policy: policy, budget: DiskScanBudget(), slice: DiskScanBudget(), excluding: []).complete)
}
@Test func discoveryRetriesBudgetExhaustionAndFDARevocationDropsProtectedCursors() async throws {
    let home = try disk59Fixture(), access = DiskAccessSwitch()
    defer { try? FileManager.default.removeItem(at: home) }
    try disk59File(home.appendingPathComponent("Documents/data"))
    let worker = DiskScanWorker(home: home, probe: { access.granted }, cacheURL: nil)
    #expect(!DiskRootPlan.discovery(home: home, policy: ProtectedPaths(home: home.path), budget: DiskScanBudget(limit: 0)).complete)
    _ = worker.load(seconds: 0)
    let complete = worker.load()
    #expect(complete.contains { $0.path == home.appendingPathComponent("Documents").path && $0.complete })
    access.revoke()
    #expect(!worker.refreshAccess())
    #expect(!worker.cachedEstimates().contains { $0.path.hasPrefix(home.appendingPathComponent("Documents").path) })
    let discovered = worker.load()
    #expect(discovered.contains { $0.path == home.appendingPathComponent("new").path } == false)
    try disk59File(home.appendingPathComponent("new/data"))
    worker.discoveredAt = .distantPast
    #expect(worker.load().contains { $0.path == home.appendingPathComponent("new").path })
}
private final class DiskAccessSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = true
    var granted: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func revoke() { lock.lock(); value = false; lock.unlock() }
}
@Test func completedCacheRelaunchIsImmediateAndMtimeReuseDoesNotReenumerate() async throws {
    let home = try disk59Fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let root = home.appendingPathComponent("dev"), cache = home.appendingPathComponent("cache.json")
    try disk59File(root.appendingPathComponent("data"))
    let first = DiskEstimates(home: home, probe: { false }, cacheURL: cache)
    let measured = await first.load(roots: [root])
    let resumed = DiskEstimates(home: home, probe: { false }, cacheURL: cache)
    let start = ProcessInfo.processInfo.systemUptime
    #expect(await resumed.cachedEstimates() == measured)
    #expect(ProcessInfo.processInfo.systemUptime - start < 2)
    let entries = await resumed.scanEntries()
    #expect(await resumed.load(roots: [root]) == measured)
    #expect(await resumed.scanEntries() == entries)
    let realHome = FileManager.default.homeDirectoryForCurrentUser.path
    let shown = EvidencePath.display(home.path)
    if home.path == realHome || home.path.hasPrefix(realHome + "/") {
        #expect(shown.hasPrefix("~/"))
        #expect(!shown.contains(realHome))
    } else {
        #expect(shown == home.path)
    }
    #expect(EvidencePath.display(realHome + "/Library") == "~/Library")
}
@Test func rootDeviceMismatchRejectsEnumerationBeforeReadingChildren() throws {
    let home = try disk59Fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    try disk59File(home.appendingPathComponent("child/data"))
    let cursor = DiskScanCursor(), log = DiskAccessLog()
    let estimate = cursor.advance(path: home.path, policy: ProtectedPaths(home: home.path, observer: { log.record($0) }),
                                  budget: DiskScanBudget(), slice: DiskScanBudget(), excluding: [], expectedDevice: Int64.min)
    #expect(estimate.bytes == nil && !estimate.complete && cursor.openDescriptors == 0)
    #expect(!log.values.contains { $0.hasPrefix(home.path + "/") })
}
@Test func datalessMaterializationIsDisabledAtTheOperatingSystemBoundary() {
    #expect(DiskIOPolicy.disableMaterialization())
    #expect(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS) == IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
}
@Test func bulkResumeAcrossManyBatchesCountsEachLongNamedEntryExactlyOnce() throws {
    let home = try disk59Fixture(), root = home.appendingPathComponent("dev")
    defer { try? FileManager.default.removeItem(at: home) }
    let suffix = String(repeating: "long", count: 40)
    for index in 0..<2000 { try disk59File(root.appendingPathComponent("\(index)-\(suffix)")) }
    let cursor = DiskScanCursor(), policy = ProtectedPaths(home: home.path)
    for _ in 0..<10 {
        _ = cursor.advance(path: root.path, policy: policy, budget: DiskScanBudget(limit: 500), slice: DiskScanBudget(limit: 500), excluding: [])
        #expect(cursor.openDescriptors == 0)
        if cursor.finished { break }
    }
    #expect(cursor.finished && cursor.bytes == 2000 * 4096)
    #expect(cursor.entries == 2000)
    #expect(cursor.bytes == DiskEstimates.measure(root: root).bytes)
}

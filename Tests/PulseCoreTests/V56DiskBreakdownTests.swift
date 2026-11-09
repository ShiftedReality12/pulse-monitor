import Foundation
import Testing
@testable import PulseCore

@Test func diskBreakdownUsesMeasuredDiskNotSessionRAMAndAvoidsOverlap() {
    var session = ProcessGroup(id: "AI", title: "Claude", members: [52], resident: 9_000_000_000, cpu: 3, limited: false)
    session.category = "AI session"; session.cwd = "/work/slate"
    let now = Date()
    let estimates = [DiskEstimate(path: "/work/slate", bytes: 100_000, complete: true, date: now),
                     DiskEstimate(path: "/work", bytes: 300_000, complete: true, date: now),
                     DiskEstimate(path: "/cache", bytes: 20_000, complete: false, date: now)]
    let buckets = DiskBreakdown.buckets(estimates: estimates, sessions: [session])
    #expect(buckets.count == 2)
    #expect(buckets[0].isProject && buckets[0].bytes == 100_000)
    #expect(buckets[1].partial && buckets[1].bytes == 20_000)
    #expect(!buckets.contains { $0.bytes == session.resident || $0.path == "/work" })
    session.cwd = "/"; #expect(DiskBreakdown.projectPaths([session]).isEmpty)
    session.cwd = FileManager.default.homeDirectoryForCurrentUser.path
    #expect(DiskBreakdown.projectPaths([session]).isEmpty)
}
@Test func diskEstimatorCacheRespectsDifferentRequestedRoots() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/v56-disk-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
    try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 65_536).write(to: a.appendingPathComponent("one"))
    try Data(repeating: 2, count: 131_072).write(to: b.appendingPathComponent("two"))
    let service = DiskEstimates(cacheURL: nil)
    let first = await service.load(roots: [a]), second = await service.load(roots: [b])
    #expect(first[0].path == a.path && second[0].path == b.path)
    #expect((second[0].bytes ?? 0) > (first[0].bytes ?? 0))
    var session = ProcessGroup(id: "project", title: "AI", members: [1], resident: 999, cpu: 0, limited: false)
    session.category = "AI session"; session.cwd = b.path
    let buckets = DiskBreakdown.buckets(estimates: second, sessions: [session])
    #expect(buckets.first?.bytes == second[0].bytes && buckets.first?.isProject == true)
}
@Test func diskScanMeasuresAFolderReachedThroughTmp() async throws {
    let root = URL(fileURLWithPath: "/tmp/pulse-tmp-root-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(repeating: 1, count: 4096).write(to: root.appendingPathComponent("one"))
    let service = DiskEstimates(home: root, probe: { false }, cacheURL: nil)
    let loaded = await service.load(roots: [root])
    let estimate = try #require(loaded.first { $0.path == root.path })
    #expect((estimate.bytes ?? 0) > 0)
    #expect(estimate.complete)
}

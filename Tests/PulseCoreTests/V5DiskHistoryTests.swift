import Foundation
import Testing
@testable import PulseCore

private func fixtureDirectory() throws -> URL {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let directory = repo.appendingPathComponent(".build/disk-fixture-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
@Test func diskEstimatesBoundWorkSkipLinksAndLabelMissing() throws {
    let root = try fixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(repeating: 42, count: 65_536).write(to: root.appendingPathComponent("file"))
    let complete = DiskEstimates.measure(root: root)
    #expect(complete.complete && (complete.bytes ?? 0) > 0)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
    #expect(DiskEstimates.measure(root: root).bytes == complete.bytes)
    #expect(!DiskEstimates.measure(root: root, limit: 0).complete)
    #expect(DiskEstimates.measure(root: root.appendingPathComponent("missing")).bytes == nil)
    #expect(DiskEstimates.measure(root: root.appendingPathComponent("loop")).bytes == nil)
}
@Test func diskViewCacheUsesActualMeasuredOutput() async throws {
    let root = try fixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(repeating: 42, count: 65_536).write(to: root.appendingPathComponent("one"))
    let service = DiskEstimates(cacheURL: nil)
    let first = await service.load(roots: [root])
    #expect(first[0].bytes == DiskEstimates.measure(root: root).bytes)
    try Data(repeating: 43, count: 65_536).write(to: root.appendingPathComponent("two"))
    let cached = await service.load(roots: [root])
    #expect(cached[0].complete && cached[0].bytes == 2 * 65_536)
    #expect(DiskEstimates.measure(root: root).bytes == cached[0].bytes)
}
@Test func ownerTrendBoundedAndRemovedOwnersLoseHistory() {
    var history = OwnerHistory()
    var groups = [ProcessGroup(id: "owner", title: "owner", members: [1], resident: 1_000_000, cpu: 3, limited: false)]
    groups[0].hasVerifiedIdentity = true
    for _ in 0..<100 { history.apply(to: &groups) }
    #expect(groups[0].memoryTrend.count == 30)
    let owner = groups[0]
    groups = []; history.apply(to: &groups)
    groups = [owner]; history.apply(to: &groups)
    #expect(groups[0].memoryTrend == [1])
}

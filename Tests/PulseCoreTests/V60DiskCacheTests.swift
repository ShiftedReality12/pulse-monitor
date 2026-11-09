import Foundation
import Testing
@testable import PulseCore

@Test func diskCacheRoundTripResumeCorruptionAndThrottle() async throws {
    let home = try disk59Fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let root = home.appendingPathComponent("dev"), file = home.appendingPathComponent("cache.json")
    for index in 0..<90 { try disk59File(root.appendingPathComponent("f\(index)")) }
    let first = DiskEstimates(home: home, probe: { false }, cacheURL: file)
    let partial = await first.load(roots: [root], limit: 10)
    #expect(partial.first?.complete == false)
    let saved = try Data(contentsOf: file)
    #expect(saved.count <= 256 * 1024)
    let resumed = DiskEstimates(home: home, probe: { false }, cacheURL: file)
    #expect(await resumed.cachedEstimates() == partial)
    let finished = await resumed.load(roots: [root])
    #expect(finished.first?.complete == true && finished.first?.bytes == 90 * 4096)
    #expect(try Data(contentsOf: file) == saved)
    try Data("broken".utf8).write(to: file)
    let corrupt = DiskEstimates(home: home, probe: { false }, cacheURL: file)
    #expect(await corrupt.cachedEstimates().isEmpty)
    #expect(await corrupt.load(roots: [root]).first?.bytes == 90 * 4096)
}
@Test func unchangedEmptyDirectorySkipIsSafeAndChangedDirectoryIsRescanned() throws {
    let home = try disk59Fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let root = home.appendingPathComponent("empty")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let policy = ProtectedPaths(home: home.path)
    let first = DiskScanCursor()
    #expect(first.advance(path: root.path, policy: policy, budget: DiskScanBudget(), slice: DiskScanBudget(), excluding: []).complete)
    let next = DiskScanCursor(emptyDirectories: first.emptyDirectories)
    #expect(next.advance(path: root.path, policy: policy, budget: DiskScanBudget(), slice: DiskScanBudget(), excluding: []).complete)
    #expect(next.skippedDirectories == 1)
    try disk59File(root.appendingPathComponent("new"))
    let changed = DiskScanCursor(emptyDirectories: first.emptyDirectories)
    #expect(changed.advance(path: root.path, policy: policy, budget: DiskScanBudget(), slice: DiskScanBudget(), excluding: []).bytes == 4096)
    #expect(changed.skippedDirectories == 0)
}
@Test func changedDirectoryInvalidatesPersistedCookieAndFutureOrOversizedCachesAreIgnored() async throws {
    let home = try disk59Fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let root = home.appendingPathComponent("dev"), file = home.appendingPathComponent("cache.json")
    for index in 0..<20 { try disk59File(root.appendingPathComponent("f\(index)")) }
    let first = DiskEstimates(home: home, probe: { false }, cacheURL: file)
    #expect(await first.load(roots: [root], limit: 4).first?.complete == false)
    let saved = try Data(contentsOf: file)
    try disk59File(root.appendingPathComponent("added"))
    let resumed = DiskEstimates(home: home, probe: { false }, cacheURL: file)
    let result = await resumed.load(roots: [root])
    #expect(result.first?.complete == true && result.first?.bytes == 21 * 4096)
    var future = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
    for version in [1, 99] {
        future["version"] = version
        try JSONSerialization.data(withJSONObject: future).write(to: file)
        #expect(await DiskEstimates(home: home, probe: { false }, cacheURL: file).cachedEstimates().isEmpty)
    }
    try Data(repeating: 32, count: 256 * 1024 + 1).write(to: file)
    #expect(await DiskEstimates(home: home, probe: { false }, cacheURL: file).cachedEstimates().isEmpty)
}

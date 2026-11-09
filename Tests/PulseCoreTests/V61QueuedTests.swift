import Foundation
import Dispatch
import Testing
@testable import PulseCore
@testable import PulseApp

@Test func cancellationCrossesTheUtilityQueueBeforeAnyChildIsEnumerated() async throws {
    let home = try disk59Fixture(), root = home.appendingPathComponent("dev")
    defer { try? FileManager.default.removeItem(at: home) }
    try disk59File(root.appendingPathComponent("child/data"))
    let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    let service = DiskEstimates(home: home, probe: { false }, observer: { path in
        if path == root.path { started.signal(); release.wait() }
    }, cacheURL: nil)
    let task = Task { await service.load(roots: [root]) }
    let ready = await withCheckedContinuation { continuation in
        DispatchQueue.global().async { continuation.resume(returning: started.wait(timeout: .now() + 2)) }
    }
    #expect(ready == .success)
    task.cancel(); release.signal()
    _ = await task.value
    #expect(await service.scanEntries()[root.path] == 0)
    #expect(await service.openDirectoryCount() == 0)
}
@MainActor @Test func droppedTopOwnerKeepsHistoryForSixtySecondsWithinTwentyFourKeys() {
    let model = ProcessDrilldownModel(); model.open(.memory)
    var groups = (0..<13).map { ProcessGroup(id: "g\($0)", title: "Owner", members: [], resident: UInt64(100 + $0), cpu: 0, limited: false) }
    model.record(groups: groups, sampledAt: Date(timeIntervalSince1970: 100))
    groups[0].resident = 1000
    model.record(groups: groups, sampledAt: Date(timeIntervalSince1970: 106)) // g1 drops from rank 12.
    #expect(model.history.samples(for: "g1", at: 106).count == 2)
    #expect(model.trends.count == 12 && model.history.keys.count <= 24)
    groups.removeAll { $0.id == "g1" }
    model.record(groups: groups, sampledAt: Date(timeIntervalSince1970: 120))
    #expect(!model.history.samples(for: "g1", at: 120).isEmpty)
    model.record(groups: groups, sampledAt: Date(timeIntervalSince1970: 165))
    #expect(model.history.keys.contains("g1"))
    model.record(groups: groups, sampledAt: Date(timeIntervalSince1970: 167))
    #expect(!model.history.keys.contains("g1"))
}
@Test func providerTimeoutKillsNonExecGrandchildrenBeforeTheyCanContinue() async throws {
    let home = try disk59Fixture(), script = home.appendingPathComponent("usage")
    defer { try? FileManager.default.removeItem(at: home) }
    try Data("#!/bin/sh\n( /bin/sleep 0.3; printf survived > \"$0.survived\" ) &\nwait\n".utf8).write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
    #expect(ProviderCommand.read(executable: script, arguments: [], timeout: 0.05) == nil)
    try await Task.sleep(for: .milliseconds(450))
    #expect(!FileManager.default.fileExists(atPath: script.path + ".survived"))
}
@Test func firstScanUsesWholeProcessCreditAndNeverSpendsMenuCredit() {
    var duty = DiskScanDuty()
    duty.reset(wall: 100, cpu: 5)
    #expect(duty.allowance(wall: 160, cpu: 5.84, fullWindow: false) == 0)
    let credit = duty.allowance(wall: 160, cpu: 5.84, fullWindow: true)
    #expect(credit > 0 && credit <= 0.02)
    #expect(duty.allowance(wall: 160, cpu: 6.2, fullWindow: true) == 0)
    #expect(duty.allowance(wall: 100, cpu: 5, fullWindow: true) == 0)
}
@Test func idleTimeCannotAccumulateACpuBurstAndRetainedDescriptorsStayBounded() async throws {
    var duty = DiskScanDuty(); duty.reset(wall: 0, cpu: 0)
    _ = duty.allowance(wall: 3600, cpu: 36, fullWindow: true)
    #expect(duty.allowance(wall: 3600, cpu: 36.02, fullWindow: true) == 0)
    let home = try disk59Fixture(), root = home.appendingPathComponent("dev")
    defer { try? FileManager.default.removeItem(at: home) }
    let deep = (0..<36).reduce(root) { path, _ in path.appendingPathComponent("level") }
    try disk59File(deep.appendingPathComponent("data"))
    let service = DiskEstimates(home: home, probe: { false }, cacheURL: nil)
    var result: [DiskEstimate] = []
    for _ in 0..<100 {
        result = await service.load(roots: [root], limit: 2)
        #expect(await service.openDirectoryCount() <= 16)
        if result.allSatisfy(\.complete) { break }
    }
    #expect(result.first?.complete == true && result.first?.bytes == 4096)
}
@Test func benchmarkCountsWorkWhenARefreshResetsTheCursorCounter() {
    #expect(DiskBenchmark.advancedEntries(previous: ["root": 400_000], current: ["root": 20_000]) == 20_000)
    #expect(DiskBenchmark.advancedEntries(previous: ["root": 10_000], current: ["root": 20_000]) == 10_000)
    #expect(DiskBenchmark.advancedEntries(previous: [:], current: ["root": 20_000]) == 20_000)
}
@Test func suspendedWideDirectoryTreeNeverRecountsCompletedChildren() throws {
    let home = try disk59Fixture(), root = home.appendingPathComponent("dev")
    defer { try? FileManager.default.removeItem(at: home) }
    let suffix = String(repeating: "wide", count: 35)
    for index in 0..<800 {
        try disk59File(root.appendingPathComponent("\(index)-\(suffix)/one"))
        try disk59File(root.appendingPathComponent("\(index)-\(suffix)/two"))
    }
    let cursor = DiskScanCursor(), policy = ProtectedPaths(home: home.path)
    for _ in 0..<10 {
        _ = cursor.advance(path: root.path, policy: policy, budget: DiskScanBudget(limit: 1500), slice: DiskScanBudget(limit: 1500), excluding: [])
        if cursor.finished { break }
    }
    #expect(cursor.finished && cursor.bytes == 1600 * 4096)
    #expect(cursor.entries == 2400)
}

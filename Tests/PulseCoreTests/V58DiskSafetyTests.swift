import Foundation
import Testing
@testable import PulseCore

@Test func protectedPolicyRejectsEveryRootChildAndDataVolumeAlias() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let policy = ProtectedPaths.shared
    for name in ["Music", "Pictures", "Movies", "Library", "Desktop", "Documents", "Downloads"] {
        for suffix in ["", "/child", "/nested/file", "/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
                       "/Group Containers/group/data", "/Mobile Documents/com~apple~CloudDocs/data"] {
            let path = home + "/" + name + suffix
            #expect(!policy.allows(path))
            #expect(!policy.allows(path.uppercased()))
            #expect(!policy.allows("/System/Volumes/Data" + path))
            #expect(DiskEstimates.measure(root: URL(fileURLWithPath: path)).bytes == nil)
        }
    }
    #expect(!policy.allows("/" + ["Users", "other", "Music", "file"].joined(separator: "/")))
    #expect(!policy.allows("/Volumes/External/project"))
    #expect(!policy.allows("/Network/server/project"))
    for root in DiskEstimates.defaultRoots { #expect(policy.allows(root.path)) }
    // Only assert names that exist on this Mac; do not hard-code personal folder names.
    for name in ["dev", ".claude", ".codex", ".cache", ".npm"] {
        let path = home + "/" + name
        guard FileManager.default.fileExists(atPath: path) else { continue }
        #expect(DiskEstimates.defaultRoots.contains { $0.path == path })
    }
    #expect(policy.allows(home + "/Musical/project"))
}
@Test func fakeLargeTreeStopsAtEntryAndWallBudgets() {
    let budget = DiskScanBudget(limit: 900_000, seconds: 90, clock: { 0 })
    var visited = 0
    for _ in 0..<300_000 { if budget.take() { visited += 1 } else { break } }
    #expect(visited == 200_000 && budget.entries == 200_000 && !budget.available)
    var time = 0.0
    let timed = DiskScanBudget(seconds: 99, clock: { time })
    #expect(timed.take())
    time = 2.999; #expect(timed.take())
    time = 3; #expect(!timed.take())
}
@Test func protectedSegmentIsUsedMinusSelectedMeasuredMinusOther() {
    var snapshot = healthySnapshot(); snapshot.diskTotal = 100; snapshot.diskFree = 10
    let buckets = [40, 20, 10].enumerated().map { index, bytes in
        DiskBucket(path: "/folder\(index)", label: "folder\(index)", bytes: UInt64(bytes), partial: false, isProject: false)
    }
    let composition = DiskComposition(snapshot: snapshot, buckets: buckets, folderLimit: 1)
    #expect(composition.segments.map(\.bytes) == [40, 30, 20, 10])
    #expect(composition.segments.filter { $0.id == "protected" }.count == 1)
    #expect(composition.segments.first { $0.id == "protected" }?.partial == true)
    #expect(composition.segments.reduce(0) { $0 + $1.bytes } == 100)
    #expect(DiskComposition(snapshot: snapshot, buckets: []).segments.map(\.bytes) == [90, 10])
    let huge = DiskBucket(path: "/huge", label: "huge", bytes: .max, partial: true, isProject: false)
    #expect(DiskComposition(snapshot: snapshot, buckets: [huge, huge]).segments.map(\.bytes) == [90, 10])
}
@Test func walkerSkipsProtectedChildrenAndBothKindsOfSymlinkEscape() throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let root = repo.appendingPathComponent(".build/v58-safety-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let safe = root.appendingPathComponent("safe"), blocked = root.appendingPathComponent("Music")
    for folder in [safe, blocked] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    try Data(repeating: 1, count: 65_536).write(to: safe.appendingPathComponent("one"))
    try Data(repeating: 2, count: 131_072).write(to: blocked.appendingPathComponent("secret"))
    try FileManager.default.createSymbolicLink(at: safe.appendingPathComponent("escape"), withDestinationURL: blocked)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: safe)
    var scanner = DiskWalker(policy: ProtectedPaths(home: root.path), budget: DiskScanBudget())
    let result = scanner.measure(root)
    #expect(result.bytes == DiskEstimates.measure(root: safe).bytes)
    #expect(!result.complete && (result.bytes ?? 0) > 0)
    #expect(DiskEstimates.measure(root: root.appendingPathComponent("alias")).bytes == nil)
    #expect(DiskEstimates.measure(root: root.appendingPathComponent("alias/escape")).bytes == nil)
    let limited = DiskEstimates.measure(root: root, limit: 1)
    #expect(!limited.complete && limited.bytes == 0)
    #expect(DiskEstimates.measure(root: root, seconds: 0).bytes == nil)
}
@Test func onePassBudgetIsSharedAcrossRootsAndCacheRetainsResults() async throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let root = repo.appendingPathComponent(".build/v58-budget-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var roots: [URL] = []
    for index in 0..<4 {
        let folder = root.appendingPathComponent("root\(index)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in 0..<100 { try Data(repeating: 1, count: 4096).write(to: folder.appendingPathComponent("file\(file)")) }
        roots.append(folder)
    }
    let service = DiskEstimates(cacheURL: nil), start = ProcessInfo.processInfo.systemUptime
    let result = await service.load(roots: roots, limit: 40)
    #expect(ProcessInfo.processInfo.systemUptime - start < 3)
    #expect(result.filter { ($0.bytes ?? 0) > 0 }.count == 4)
    #expect(result.allSatisfy { !$0.complete })
    #expect(result.reduce(UInt64(0)) { $0 + ($1.bytes ?? 0) } <= 40 * 4096)
    let resumed = await service.load(roots: roots)
    #expect(resumed.allSatisfy { $0.complete })
    #expect(resumed.reduce(UInt64(0)) { $0 + ($1.bytes ?? 0) } > result.reduce(UInt64(0)) { $0 + ($1.bytes ?? 0) })
    #expect(await service.load(roots: roots) == resumed)
}

import Foundation
import Darwin
import Testing
@testable import PulseCore

final class DiskAccessLog: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    func record(_ path: String) { lock.lock(); defer { lock.unlock() }; paths.append(path) }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return paths }
}
func disk59Fixture() throws -> URL {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let root = repo.appendingPathComponent(".build/v59-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
func disk59File(_ path: URL, size: Int = 4096) throws {
    try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 42, count: size).write(to: path)
}
@Test func deniedFDAHasNoProtectedFilesystemAccessAndAllowsOnlyDerivedData() async throws {
    let home = try disk59Fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let protected = ["Music", "Pictures", "Movies", "Desktop", "Documents", "Downloads"]
    for name in protected + ["dev", ".claude", ".codex", "private-vault", ".cache", "LargeFolder"] {
        try disk59File(home.appendingPathComponent(name + "/data"))
    }
    try disk59File(home.appendingPathComponent(DiskRootPlan.derived + "/data"))
    try disk59File(home.appendingPathComponent("Library/Other/data"))
    let log = DiskAccessLog(), probes = DiskAccessLog()
    let service = DiskEstimates(home: home, probe: { probes.record("probe"); return false }, observer: { log.record($0) })
    let estimates = await service.load()
    #expect(await service.fullDiskAccessGranted() == false)
    #expect(probes.values == ["probe"])
    for name in protected {
        let path = home.appendingPathComponent(name).path
        #expect(!log.values.contains { $0 == path || $0.hasPrefix(path + "/") })
        #expect(!estimates.contains { $0.path == path })
    }
    let library = home.appendingPathComponent("Library").path
    let derived = home.appendingPathComponent(DiskRootPlan.derived).path
    #expect(!log.values.contains { $0.hasPrefix(library + "/Other") })
    #expect(estimates.first { $0.path == derived }?.bytes == 4096)
    for name in ["dev", ".claude", ".codex", "private-vault", ".cache", "LargeFolder"] {
        #expect(estimates.first { $0.path == home.appendingPathComponent(name).path }?.bytes == 4096)
    }
    let denied = await service.load(roots: protected.map { home.appendingPathComponent($0) })
    #expect(denied.allSatisfy { $0.bytes == nil })
    #expect(probes.values.count == 2)
    for name in protected {
        let path = home.appendingPathComponent(name).path
        #expect(!log.values.contains { $0 == path || $0.hasPrefix(path + "/") })
    }
}
@Test func grantedFDAConsumesProtectedICloudAndSingleAllocatedDockerStat() async throws {
    let home = try disk59Fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    for name in ["Music", "Pictures", "Movies", "Desktop", "Documents", "Downloads"] {
        try disk59File(home.appendingPathComponent(name + "/data"))
    }
    try disk59File(home.appendingPathComponent(DiskRootPlan.derived + "/data"))
    try disk59File(home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/data"))
    let docker = home.appendingPathComponent(DiskRootPlan.docker)
    try disk59File(docker)
    let handle = try FileHandle(forWritingTo: docker)
    try handle.truncate(atOffset: 128 * 1024 * 1024); try handle.close()
    var info = stat(); #expect(lstat(docker.path, &info) == 0)
    let allocated = UInt64(info.st_blocks) * 512
    #expect(allocated < UInt64(info.st_size))
    let log = DiskAccessLog()
    let service = DiskEstimates(home: home, probe: { true }, observer: { log.record($0) })
    let estimates = await service.load()
    #expect(await service.fullDiskAccessGranted())
    #expect(estimates.first { $0.path == docker.path }?.bytes == allocated)
    #expect(log.values.filter { $0 == docker.path }.count == 1)
    #expect(estimates.first { $0.path == home.appendingPathComponent("Music").path }?.bytes == 4096)
    #expect(estimates.first { $0.path == home.appendingPathComponent("Library").path }?.bytes == 4096)
    #expect(estimates.first { $0.path == home.appendingPathComponent(DiskRootPlan.derived).path }?.bytes == 4096)
    var snapshot = healthySnapshot(); snapshot.diskTotal = 100_000_000; snapshot.diskFree = 10_000_000
    let buckets = DiskBreakdown.buckets(estimates: estimates.filter { $0.path.hasPrefix(home.path) }, sessions: [])
    let composition = DiskComposition(snapshot: snapshot, buckets: buckets, fullDiskAccess: true)
    #expect(composition.segments.contains { $0.label == "Unmeasured" })
    #expect(!composition.segments.contains { $0.label == "Protected by macOS" })
}
@Test func fdaSentinelOnlyOpensClosesAndRejectsMissingOrSymlink() throws {
    let home = try disk59Fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(!FullDiskAccess.granted(home: home))
    let sentinel = home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
    try disk59File(sentinel)
    #expect(FullDiskAccess.granted(home: home))
    let attributes = try FileManager.default.attributesOfItem(atPath: sentinel.path)
    #expect(attributes[.size] as? Int == 4096)
    try FileManager.default.removeItem(at: sentinel)
    try FileManager.default.createSymbolicLink(at: sentinel, withDestinationURL: home)
    #expect(!FullDiskAccess.granted(home: home))
}

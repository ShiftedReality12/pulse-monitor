import Foundation
import Testing
@testable import PulseCore

@Test func perRootSlicesResumeWithoutStarvationAndCarveNodeModulesOutOfParents() async throws {
    let home = try disk59Fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let roots = [home.appendingPathComponent("dev"), home.appendingPathComponent(".codex")]
    for root in roots {
        for index in 0..<30 { try disk59File(root.appendingPathComponent("file\(index)")) }
        for index in 0..<30 { try disk59File(root.appendingPathComponent("node_modules/package/file\(index)")) }
    }
    let service = DiskEstimates(home: home, probe: { false })
    var previous: [String: UInt64] = [:], estimates: [DiskEstimate] = []
    for pass in 0..<30 {
        estimates = await service.load(roots: roots, limit: 16)
        for root in roots {
            let estimate = try #require(estimates.first { $0.path == root.path })
            #expect((estimate.bytes ?? 0) >= (previous[root.path] ?? 0))
            previous[root.path] = estimate.bytes
            if pass == 0 { #expect(estimate.bytes != nil && !estimate.complete) }
        }
        if estimates.allSatisfy({ $0.complete }) { break }
    }
    #expect(estimates.allSatisfy { $0.complete })
    for root in roots { #expect(estimates.first { $0.path == root.path }?.bytes == 30 * 4096) }
    let nodes = try #require(estimates.first { $0.path == DiskRootPlan.nodes })
    #expect(nodes.bytes == 60 * 4096)
    let buckets = DiskBreakdown.buckets(estimates: estimates, sessions: [])
    #expect(buckets.first { $0.label == "node_modules" }?.bytes == nodes.bytes)
    #expect(buckets.reduce(UInt64(0)) { $0 + $1.bytes } == 120 * 4096)
    #expect(await service.load(roots: roots) == estimates)
}
@Test func nestedSessionCannotReplaceKeyRootAndPartitionChangeCannotDoubleCount() async throws {
    let home = try disk59Fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let dev = home.appendingPathComponent("dev"), project = dev.appendingPathComponent("project")
    try disk59File(dev.appendingPathComponent("other"))
    try disk59File(project.appendingPathComponent("data"))
    let service = DiskEstimates(home: home, probe: { false })
    let before = await service.load(roots: [dev])
    #expect(before.first?.bytes == 8192)
    let after = await service.load(roots: [dev, project])
    #expect(after.count == 2 && after.allSatisfy { $0.bytes == 4096 })
    var session = ProcessGroup(id: "AI", title: "Codex", members: [1], resident: 1, cpu: 0, limited: false)
    session.category = "AI session"; session.cwd = project.path
    let buckets = DiskBreakdown.buckets(estimates: after, sessions: [session])
    #expect(buckets.count == 2 && buckets.reduce(UInt64(0)) { $0 + $1.bytes } == 8192)
    let actualHome = FileManager.default.homeDirectoryForCurrentUser
    session.cwd = actualHome.appendingPathComponent("dev/project").path
    #expect(DiskBreakdown.roots(sessions: [session]).contains { $0.path == actualHome.appendingPathComponent("dev").path })
}
@Test func topSegmentsAreSortedHaveOtherMeasuredAndNoZeroRows() {
    var snapshot = healthySnapshot(); snapshot.diskTotal = 100; snapshot.diskFree = 0
    let buckets = [0, 10, 30, 20].enumerated().map { index, value in
        DiskBucket(path: "/\(index)", label: "\(index)", bytes: UInt64(value), partial: index == 2, isProject: false)
    }
    let composition = DiskComposition(snapshot: snapshot, buckets: buckets, folderLimit: 2)
    #expect(composition.segments.map(\.bytes) == [30, 20, 10, 40])
    #expect(composition.segments.map(\.label) == ["2", "3", "Other measured", "Protected by macOS"])
    #expect(composition.segments.first?.partial == true)
    #expect(composition.segments.allSatisfy { $0.bytes > 0 })
    #expect(composition.segments.reduce(0) { $0 + $1.bytes } == 100)
}

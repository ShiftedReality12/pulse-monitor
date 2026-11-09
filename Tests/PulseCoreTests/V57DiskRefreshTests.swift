import Foundation
import Testing
@testable import PulseApp
@testable import PulseCore

@Test func diskRootsAreCanonicalDeduplicatedAndSortedUnderSnapshotChurn() {
    var a = ProcessGroup(id: "a", title: "Codex", members: [1], resident: 10, cpu: 2, limited: false)
    a.category = "AI session"; a.cwd = "/work/a/../project/"
    var b = a; b.id = "b"; b.cwd = "/work/project"
    let first = DiskBreakdown.roots(sessions: [a, b]).map(\.path)
    #expect(first == Array(Set(first)).sorted())
    for index in 0..<100 {
        a.cpu = Double(index); a.resident = UInt64(index); a.title = "Codex \(index)"
        #expect(DiskBreakdown.roots(sessions: index.isMultiple(of: 2) ? [a, b] : [b, a]).map(\.path) == first)
    }
}
@MainActor @Test func snapshotChurnKeepsCompletedEstimatesVisibleDuringMaterialRefresh() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/v57-refresh-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
    for folder in [a, b] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 65_536).write(to: folder.appendingPathComponent("data"))
    }
    var session = ProcessGroup(id: "a", title: "Codex", members: [1], resident: 10, cpu: 2, limited: false)
    session.category = "AI session"; session.cwd = a.path
    let model = DiskUsageModel(service: DiskEstimates(home: root, probe: { false }, cacheURL: nil), cpuSample: { 0 })
    defer { model.update(visible: false, sessions: []) }
    model.update(visible: true, sessions: [session])
    let deadline = ProcessInfo.processInfo.systemUptime + 30
    while !model.estimates.contains(where: { $0.path == a.path }) && ProcessInfo.processInfo.systemUptime < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    let original = try #require(model.estimates.first { $0.path == a.path })
    for index in 0..<200 {
        session.cpu = Double(index); session.resident = UInt64(index)
        session.cwd = index.isMultiple(of: 2) ? a.path + "/" : a.appendingPathComponent("../a").path
        var duplicate = session; duplicate.id = "duplicate"
        model.update(visible: true, sessions: index.isMultiple(of: 2) ? [session, duplicate] : [duplicate, session])
        #expect(!model.loading)
        #expect(model.estimates.first { $0.path == a.path } == original)
    }
    session.cwd = b.path
    model.update(visible: true, sessions: [session])
    #expect(!model.loading) // A refresh must retain the completed display, not claim initial loading.
    #expect(model.estimates.first { $0.path == a.path } == original)
    while !model.estimates.contains(where: { $0.path == b.path }) && ProcessInfo.processInfo.systemUptime < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect((model.estimates.first { $0.path == b.path }?.bytes ?? 0) > 0)
    #expect(!model.loading)
}

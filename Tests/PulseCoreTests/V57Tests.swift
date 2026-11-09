import AppKit
import Foundation
import Testing
@testable import PulseApp
@testable import PulseCore

@MainActor @Test func glanceAndOverviewShareEveryVerdictTransition() {
    let monitor = Monitor(); monitor.stopSampling()
    let glance = GlanceView(monitor: monitor, openOverview: {})
    let overview = PulseWindow(monitor: monitor)
    var snapshot = healthySnapshot()
    for signal in [HealthSignal.none, .memory, .cpu, .disk, .heat, .unavailable] {
        snapshot = healthySnapshot()
        switch signal {
        case .memory: snapshot.pressure = .warning
        case .cpu: snapshot.cpu = 95; snapshot.highCPUDuration = 30
        case .disk: snapshot.diskFree = 8_000_000_000
        case .heat: snapshot.temperature = 99
        case .unavailable: snapshot.cpu = nil
        case .none: break
        }
        #expect(snapshot.signal == signal)
        monitor.snapshot = snapshot
        #expect(glance.monitor === overview.monitor)
        #expect(glance.monitor.verdict == overview.monitor.verdict)
        let expected: [HealthSignal: String] = [.none: "Your Mac is OK", .memory: "Memory is tight", .cpu: "Your Mac is working hard", .disk: "Disk is almost full: 8.0 GB left", .heat: "Your Mac is running hot", .unavailable: "Some readings are unavailable"]
        #expect(monitor.verdict.headline == expected[signal])
        #expect(monitor.verdict.tone == snapshot.healthTone)
        #expect(NSImage(systemSymbolName: monitor.verdict.symbol, accessibilityDescription: nil) != nil)
    }
}
@Test func usedDiskSegmentsIncludeOtherAndFreeAtSevenPercent() {
    var snapshot = healthySnapshot()
    snapshot.diskTotal = 100_000_000_000; snapshot.diskFree = 7_000_000_000
    let buckets = [DiskBucket(path: "/large", label: "Downloads", bytes: 40_000_000_000, partial: false, isProject: false),
                   DiskBucket(path: "/AI", label: "AI · slate", bytes: 5_000_000_000, partial: true, isProject: true)]
    let composition = DiskComposition(snapshot: snapshot, buckets: buckets)
    #expect(composition.summary == "93.0 GB used · 7.0 GB free")
    #expect(composition.segments.map(\.bytes) == [40_000_000_000, 5_000_000_000, 48_000_000_000, 7_000_000_000])
    #expect(composition.segments.map(\.label) == ["Downloads", "AI · slate", "Protected by macOS", "Free"])
    #expect(composition.segments.reduce(0) { $0 + $1.bytes } == composition.total)
    let overcount = DiskComposition(snapshot: snapshot, buckets: buckets, folderLimit: 0)
    #expect(overcount.segments.map(\.bytes) == [45_000_000_000, 48_000_000_000, 7_000_000_000])
    snapshot.diskFree = 101_000_000_000
    #expect(DiskComposition(snapshot: snapshot, buckets: buckets).segments.isEmpty)
}
@Test func diskCompositionCapsAllocatedEstimatesAndSortsLargestFirst() {
    var snapshot = healthySnapshot(); snapshot.diskTotal = 100; snapshot.diskFree = 7
    let buckets = [DiskBucket(path: "/a", label: "a", bytes: 200, partial: false, isProject: false),
                   DiskBucket(path: "/b", label: "b", bytes: 100, partial: false, isProject: false),
                   DiskBucket(path: "/AI", label: "AI", bytes: 20, partial: true, isProject: true)]
    let normal = DiskComposition(snapshot: snapshot, buckets: Array(buckets.dropFirst()), folderLimit: 1)
    #expect(normal.segments.first?.label == "b")
    #expect(normal.segments.first?.partial == false)
    let clipped = DiskComposition(snapshot: snapshot, buckets: buckets)
    #expect(clipped.segments.reduce(0) { $0 + $1.bytes } == 100)
    #expect(clipped.segments.first?.bytes == 93)
    #expect(clipped.segments.last?.bytes == 7)
}
@Test func partialProcessTotalsUseOneSuffixAndAnHonestFootnote() {
    var owner = ProcessGroup(id: "p", title: "Python", members: [42], resident: 3_500_000_000, cpu: 2, limited: true)
    var snapshot = healthySnapshot(); snapshot.groups = [owner]
    #expect(HumanCopy(snapshot).ownerLine == "Biggest user: Python, 3.5 GB+")
    #expect(owner.compactMetrics == "2.0%+ CPU · 3.5 GB+")
    #expect(!owner.why.contains("at least"))
    #expect(HumanCopy.partialFootnote == "+ = some processes hidden by macOS")
    owner.limited = false; snapshot.groups = [owner]
    #expect(!HumanCopy(snapshot).ownerLine.contains("+"))
    owner.resident = nil
    #expect(owner.compactMetrics.contains("RAM unavailable"))
}
@MainActor @Test func sharedDiskLoaderPublishesWithinThirtySecondsAndReusesCache() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/v57-disk-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(repeating: 1, count: 65_536).write(to: root.appendingPathComponent("one"))
    var session = ProcessGroup(id: "project", title: "Codex", members: [42], resident: 999, cpu: 0, limited: false)
    session.category = "AI session"; session.cwd = root.path
    let model = DiskUsageModel(service: DiskEstimates(home: root, probe: { false }, cacheURL: nil), cpuSample: { 0 })
    defer { model.update(visible: false, sessions: []) }
    model.update(visible: false, sessions: [session])
    #expect(model.estimates.isEmpty && !model.loading)
    let started = ProcessInfo.processInfo.systemUptime
    model.update(visible: true, sessions: [session])
    while model.loading && ProcessInfo.processInfo.systemUptime - started < 30 {
        model.update(visible: true, sessions: [session]) // Repeated refreshes must not restart work.
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(!model.loading && ProcessInfo.processInfo.systemUptime - started < 30)
    let rootPath = root.standardizedFileURL.path
    let measured = try #require(model.estimates.first { URL(fileURLWithPath: $0.path).standardizedFileURL.path == rootPath })
    #expect(measured.bytes == DiskEstimates.measure(root: root).bytes)
    var snapshot = healthySnapshot(); snapshot.groups = [session]
    let buckets = DiskBreakdown.buckets(estimates: model.estimates, sessions: snapshot.groups)
    #expect(buckets.first { URL(fileURLWithPath: $0.path).standardizedFileURL.path == rootPath }?.bytes == measured.bytes)
    try Data(repeating: 2, count: 131_072).write(to: root.appendingPathComponent("two"))
    model.update(visible: false, sessions: []); model.update(visible: true, sessions: [session])
    #expect(!model.loading && model.estimates.first { URL(fileURLWithPath: $0.path).standardizedFileURL.path == rootPath } == measured)
    #expect((DiskEstimates.measure(root: root).bytes ?? 0) > (measured.bytes ?? 0))
    let next = root.appendingPathComponent("next")
    try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
    try Data(repeating: 3, count: 65_536).write(to: next.appendingPathComponent("three"))
    session.cwd = next.path
    model.update(visible: true, sessions: [session])
    model.update(visible: false, sessions: []) // Cancel an in-flight root change, then reopen.
    model.update(visible: true, sessions: [session])
    let nextPath = next.standardizedFileURL.path
    while !model.estimates.contains(where: { URL(fileURLWithPath: $0.path).standardizedFileURL.path == nextPath }) && ProcessInfo.processInfo.systemUptime - started < 30 {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(!model.loading)
    #expect(model.estimates.first { URL(fileURLWithPath: $0.path).standardizedFileURL.path == nextPath }?.bytes == DiskEstimates.measure(root: next).bytes)
}

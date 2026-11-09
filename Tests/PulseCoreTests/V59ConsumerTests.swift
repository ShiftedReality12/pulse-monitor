import Foundation
import Testing
@testable import PulseApp
@testable import PulseCore

@MainActor @Test func visibleDiskConsumerUsesGrantedAndDeniedProducerResults() async throws {
    let home = try disk59Fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    try disk59File(home.appendingPathComponent("dev/data"))
    try disk59File(home.appendingPathComponent("Music/data"))
    for granted in [false, true] {
        let service = DiskEstimates(home: home, probe: { granted })
        let model = DiskUsageModel(service: service, cpuSample: { 0 })
        model.update(visible: true, sessions: [])
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while model.loading && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!model.loading && model.fullDiskAccess == granted)
        #expect(model.estimates.first { $0.path == home.appendingPathComponent("dev").path }?.bytes == 4096)
        let buckets = DiskBreakdown.buckets(estimates: model.estimates, sessions: [])
        #expect(buckets.contains { $0.label == "Music" } == granted)
        #expect(model.accessHint == (granted ? "Unmeasured includes APFS use and unfinished folders." : "Give Pulse Full Disk Access to see inside"))
        var snapshot = healthySnapshot(); snapshot.diskTotal = UInt64.max; snapshot.diskFree = 10_000_000
        let composition = DiskComposition(snapshot: snapshot, buckets: buckets, fullDiskAccess: model.fullDiskAccess)
        #expect(composition.segments.allSatisfy { $0.bytes > 0 })
        #expect(composition.segments.contains { $0.label == (granted ? "Unmeasured" : "Protected by macOS") })
        model.update(visible: false, sessions: [])
    }
}

import CSensors
import Testing
@testable import PulseCore

@Test func discardedCRecordClearsSwiftBaselinesAndNewIdentityRecovers() {
    var phase = 0
    let sampler = ProcessSampler(bridge: { output, _, _, _ in
        guard let output else { return 1 }
        if phase == 1 { return 0 } // C discarded the inconsistent record.
        var process = PulseProcess()
        process.pid = 52; process.started = phase == 0 ? 100 : 200
        process.readable = 1; process.io_ok = 1; process.resident = 60_000_000
        process.cpu_ns = UInt64(phase + 1) * 1_000_000_000
        process.disk_written = UInt64(phase) * 6_000_000
        withUnsafeMutableBytes(of: &process.name) { $0.copyBytes(from: Array("codex\0".utf8)) }
        withUnsafeMutableBytes(of: &process.path) { $0.copyBytes(from: Array("/bin/codex\0".utf8)) }
        output.pointee = process; return 1
    })
    var snapshot = Snapshot()
    sampler.collect(into: &snapshot, now: 0)
    phase = 1; sampler.collect(into: &snapshot, now: 6)
    #expect(snapshot.groups.isEmpty && snapshot.processCount == 0)
    phase = 2; sampler.collect(into: &snapshot, now: 12)
    #expect(snapshot.groups.first?.cpu == nil && snapshot.groups.first?.writesPerSecond == nil)
    #expect(snapshot.groups.first?.id == "ai:52:200")
    phase = 3; sampler.collect(into: &snapshot, now: 18)
    #expect(abs((snapshot.groups.first?.cpu ?? 0) - 100 / 6) < 0.000001)
    #expect(snapshot.groups.first?.writesPerSecond == 1_000_000)
}

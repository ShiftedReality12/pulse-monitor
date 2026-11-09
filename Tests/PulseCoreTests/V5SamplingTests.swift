import Foundation
import Testing
import CSensors
@testable import PulseCore

@Test func closedWindowRefreshesOwnersSlowlyAndOpenRefreshesImmediately() {
    var calls = 0
    let processes = ProcessSampler(bridge: { _, _, _, _ in calls += 1; return 0 })
    let sampler = Sampler(processes: processes)
    _ = sampler.sample(includeProcesses: false, uptime: 0)
    #expect(calls == 2) // first reading counts and fetches; closed windows start owner history at launch
    for time in [5.0, 10, 25, 29] { _ = sampler.sample(includeProcesses: false, uptime: time) }
    #expect(calls == 2) // between 30-second closed refreshes nothing is read
    _ = sampler.sample(includeProcesses: false, uptime: 30)
    #expect(calls == 4)
    _ = sampler.sample(includeProcesses: true, uptime: 31)
    #expect(calls == 6) // opening refreshes immediately
    _ = sampler.sample(includeProcesses: true, uptime: 33)
    #expect(calls == 6)
    _ = sampler.sample(includeProcesses: false, uptime: 34)
    _ = sampler.sample(includeProcesses: true, uptime: 35)
    #expect(calls == 8) // reopening within six seconds still refreshes immediately
    _ = sampler.sample(includeProcesses: true, uptime: 41)
    #expect(calls == 10)
}
@Test func unknownIdentityPIDReuseNeverProducesWrites() {
    var identity: UInt64 = 0, bytes: UInt64 = 100
    let sampler = ProcessSampler(bridge: { output, _, _, _ in
        guard let output else { return 1 }
        var p = PulseProcess(); p.pid = 52; p.started = identity; p.readable = 1
        p.io_ok = 1; p.disk_written = bytes; p.resident = 40
        output.pointee = p; return 1
    })
    func sample(_ now: Double) -> ProcessGroup {
        var s = Snapshot(); sampler.collect(into: &s, now: now); return s.groups[0]
    }
    #expect(sample(0).writesPerSecond == nil)
    bytes = 300; #expect(sample(2).writesPerSecond == nil)
    identity = 50; #expect(sample(4).writesPerSecond == nil)
    bytes = 500; #expect(sample(6).writesPerSecond == 100)
    identity = 60; bytes = 900; #expect(sample(8).writesPerSecond == nil)
    bytes = 1_100; #expect(sample(10).writesPerSecond == 100)
    identity = 0; bytes = 1_500; #expect(sample(12).writesPerSecond == nil)
    identity = 60; bytes = 1_700; #expect(sample(14).writesPerSecond == nil)
}

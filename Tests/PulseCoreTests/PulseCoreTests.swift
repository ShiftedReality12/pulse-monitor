import Testing
import Foundation
@testable import PulseCore
@Test func cpuDeltas() {
    let old = CPUTicks(user: 10, system: 20, idle: 70)
    #expect(CPUTicks(user: 20, system: 30, idle: 150).usage(since: old) == 20)
    #expect(old.usage(since: old) == nil)
    #expect(CPUTicks(user: 5, system: 0, idle: 10).usage(since: CPUTicks(user: UInt64(UInt32.max) - 4, system: 0, idle: 0)) == 50)
}
@Test func memoryPressure() {
    #expect(Pressure.classify(1) == .normal)
    #expect(Pressure.classify(2) == .warning)
    #expect(Pressure.classify(4) == .critical)
    #expect(Pressure.classify(0) == .unavailable)
    #expect(Pressure.classify(-1) == .unavailable)
}
@Test func verdicts() {
    var s = Snapshot(); s.pressure = .normal; s.cpu = 10; s.diskFree = 100_000_000_000; s.diskTotal = 1_000_000_000_000; s.swap = 0
    #expect(s.verdict == "Your Mac is OK")
    #expect(s.detail.contains("No swap"))
    s.swap = 6_700_000_000
    #expect(s.verdict == "Your Mac is OK") // Existing swap is not evidence of current pressure.
    s.pressure = .warning; #expect(s.verdict == "Memory is tight")
    s.pressure = .critical; #expect(s.verdict == "Memory needs attention")
    s.thermal = "Serious"; #expect(s.verdict == "Your Mac is running hot")
    s.thermal = "Nominal"; s.pressure = .normal; s.diskFree = 1
    #expect(s.verdict == "Disk is almost full: 1 B left")
    s.diskFree = nil; #expect(s.verdict == "Some readings are unavailable")
}
@Test func dailyBaseline() throws {
    var base = DailyBaseline(day: "2026-10-28", boot: 100, bytes: 1_000)
    #expect(base.update(day: "2026-10-28", boot: 100, bytes: 1_500) == 500)
    #expect(base.update(day: "2026-10-28", boot: 100, bytes: 1_500) == 500)
    #expect(base.update(day: "2026-10-29", boot: 100, bytes: 2_000) == 0)
    #expect(base.update(day: "2026-10-29", boot: 101, bytes: 5) == 0)
    #expect(base.update(day: "2026-10-29", boot: 101, bytes: 2) == 0)
    #expect(try JSONDecoder().decode(DailyBaseline.self, from: JSONEncoder().encode(base)) == base)
}
@Test func grouping() {
    let groups = Attribution.groups([
        ProcessSample(pid: 1, name: "Helper", path: "/Applications/日本 App.app/Contents/Helper", resident: 10, cpu: 2),
        ProcessSample(pid: 2, name: "日本 App", path: "/Applications/日本 App.app/Contents/MacOS/Main", resident: 20, cpu: 3),
        ProcessSample(pid: 3, name: "Root denied", resident: nil, cpu: nil),
        ProcessSample(pid: 4, name: "Same", path: "/usr/bin/Same", resident: 1, cpu: 0),
        ProcessSample(pid: 5, name: "Same", path: "/opt/Same", resident: 2, cpu: 0)
    ])
    #expect(groups.count == 4)
    #expect(groups.filter { $0.title == "Same" }.count == 2)
    #expect(groups.first { $0.id == "exec:/usr/bin/Same" }?.members == [4])
    #expect(groups.first { $0.id == "exec:/opt/Same" }?.resident == 2)
    let app = groups.first { $0.id == "app:/Applications/日本 App.app" }!
    #expect(app.title == "日本 App")
    #expect(app.members == [1, 2])
    #expect(app.resident == 30)
    #expect(app.cpu == 5)
    #expect(groups.first { $0.title == "Root denied" }?.limited == true)
    #expect(groups.first { $0.title == "Root denied" }?.resident == nil)
    #expect(groups.first { $0.title == "Root denied" }?.cpu == nil)
    #expect(groups.compactMap(\.resident).reduce(0, +) == 33)
}
@Test func formattingAndUnavailable() {
    #expect(MetricFormat.bytes(0) == "0 B")
    #expect(MetricFormat.bytes(999) == "999 B")
    #expect(MetricFormat.bytes(UInt64.max).contains("GB"))
    #expect(MetricFormat.bytes(nil) == "Unavailable")
    #expect(MetricFormat.percent(nil) == "Unavailable")
    #expect(Snapshot().temperature == nil)
    #expect(Snapshot().fans.isEmpty)
}
func healthySnapshot() -> Snapshot {
    var s = Snapshot()
    s.pressure = .normal; s.cpu = 20; s.thermal = "Nominal"; s.temperature = 65
    s.diskFree = 200_000_000_000; s.diskTotal = 500_000_000_000; s.swap = 0
    s.groups = Attribution.groups([ProcessSample(pid: 1, name: "Python", resident: 10, cpu: 5)])
    s.topMemoryGroup = "Python"
    return s
}
@Test func heatVerdictAndPriority() {
    var s = healthySnapshot()
    s.temperature = 94.99; #expect(s.signal == .none)
    s.temperature = 95; #expect(s.signal == .heat)
    s.pressure = .critical; s.diskFree = 1; s.cpu = 99; s.highCPUDuration = 50
    #expect(s.signal == .heat)
    #expect(s.detail.contains("Python"))
    s.temperature = nil; s.thermal = "Serious"; #expect(s.signal == .heat)
    s.thermal = "Critical"; #expect(s.signal == .heat)
    s.thermal = "Warm"; #expect(s.signal == .memory)
}
@Test func memoryVerdictAndGrowthThreshold() {
    var s = healthySnapshot()
    s.swap = 12_000_000_000; #expect(s.signal == .none) // Occupied swap alone is not growth.
    s.swapGrowthTenMinutes = 1_000_000_000; #expect(s.signal == .none)
    s.swapGrowthTenMinutes = 1_000_000_001; #expect(s.signal == .memory)
    #expect(s.detail.contains("Python"))
    #expect(s.detail.contains("Swap grew"))
    s.diskFree = 1; s.cpu = 99; s.highCPUDuration = 50
    #expect(s.signal == .memory)
    s.swapGrowthTenMinutes = 0; s.pressure = .warning; #expect(s.signal == .memory)
    s.pressure = .critical; #expect(s.verdict == "Memory needs attention")
}
@Test func diskVerdictUsesClarifiedHeadroomPolicy() {
    var s = healthySnapshot()
    s.diskTotal = 100_000_000_000
    s.diskFree = 20_000_000_000; #expect(s.signal == .none)
    s.diskFree = 9_999_999_999; #expect(s.signal == .disk)
    #expect(s.detail.contains("Python"))
    s.cpu = 99; s.highCPUDuration = 30; #expect(s.signal == .disk)
    s.cpu = 20; s.highCPUDuration = 0; s.diskFree = 19_000_000_000
    #expect(s.signal == .disk) // Absolute headroom now warns below 20 GB.
    s.diskTotal = 0; #expect(s.signal == .unavailable)
}
@Test func sustainedCPUThreshold() {
    var s = healthySnapshot()
    s.cpu = 85; s.highCPUDuration = 30; #expect(s.signal == .none)
    s.cpu = 85.01; s.highCPUDuration = 29.99; #expect(s.signal == .none)
    s.highCPUDuration = 30; #expect(s.signal == .cpu)
    #expect(s.needsAttention)
    #expect(s.detail.contains("Python"))
    s.cpu = nil; #expect(s.signal == .unavailable)
}
@Test func temporalCPURequiresContinuousObservedSamples() {
    var tracker = VerdictTracker(), s = healthySnapshot()
    s.cpu = 90
    for time in stride(from: 0.0, through: 30.0, by: 5) { tracker.apply(to: &s, uptime: time) }
    #expect(s.highCPUDuration == 30)
    #expect(s.signal == .cpu)
    s.cpu = 85; tracker.apply(to: &s, uptime: 35); #expect(s.highCPUDuration == 0)
    s.cpu = 90; tracker.apply(to: &s, uptime: 40); #expect(s.highCPUDuration == 0)
    tracker.apply(to: &s, uptime: 80); #expect(s.highCPUDuration == 0) // Sleep/gap cannot count as sustained load.
    s.cpu = nil; tracker.apply(to: &s, uptime: 85); #expect(s.highCPUDuration == 0)
}
@Test func temporalSwapWindowResetsAndExpires() {
    var tracker = VerdictTracker(), s = healthySnapshot()
    for time in stride(from: 0.0, through: 600.0, by: 5) {
        s.swap = time == 600 ? 1_000_000_001 : 0
        tracker.apply(to: &s, uptime: time)
    }
    #expect(s.swapGrowthTenMinutes == 1_000_000_001)
    #expect(s.signal == .memory)
    for time in stride(from: 605.0, through: 1_205.0, by: 5) { tracker.apply(to: &s, uptime: time) }
    #expect(s.swapGrowthTenMinutes == 0) // Old low reading is outside the trailing ten minutes.
    s.swap = 0; tracker.apply(to: &s, uptime: 1_210); #expect(s.swapGrowthTenMinutes == 0)
    s.swap = nil; tracker.apply(to: &s, uptime: 1_215); #expect(s.swapGrowthTenMinutes == nil)
    s.swap = 2_000_000_000; tracker.apply(to: &s, uptime: 1_220); #expect(s.swapGrowthTenMinutes == 0)
}

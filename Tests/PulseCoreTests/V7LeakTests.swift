import Foundation
import Testing
@testable import PulseCore

private func item(_ bytes: UInt64, id: String = "python", members: Int = 1) -> LeakWatch.Item {
    LeakWatch.Item(id: id, title: "Python", members: members, bytes: bytes)
}
@Test func leakWatchFlagsAFiveMegabyteEveryTenSecondsClimb() {
    var watch = LeakWatch()
    var bytes: UInt64 = 20_000_000
    for step in 0..<80 { // 13 minutes of 10-second ticks
        watch.record([item(bytes), item(500_000_000, id: "steady")], at: Double(step) * 10)
        bytes += 5_000_000
    }
    let findings = watch.findings()
    #expect(findings.map(\.id) == ["python"])
    let finding = findings[0]
    #expect(abs(finding.slopePerHour - 1.8e9) < 0.1e9)
    #expect(finding.span >= 600)
    #expect(finding.explanation.contains("still climbing") && finding.explanation.contains("Python"))
    #expect(watch.trackedCount == 2)
}
@Test func leakWatchWaitsForTenMinutesOfHistory() {
    var watch = LeakWatch()
    var bytes: UInt64 = 20_000_000
    for step in 0..<50 { watch.record([item(bytes)], at: Double(step) * 10); bytes += 5_000_000 } // 8 min
    #expect(watch.findings().isEmpty)
    #expect(watch.historySpan < 600)
}
@Test func leakWatchIgnoresFlatNoisyPlateauAndSpikeThatReturned() {
    var watch = LeakWatch()
    for step in 0..<120 {
        let t = Double(step) * 20
        let noisy = 300_000_000 + UInt64(step % 7) * 2_000_000
        let plateau: UInt64 = step < 20 ? 100_000_000 + UInt64(step) * 20_000_000 : 500_000_000
        let spike: UInt64 = (40..<50).contains(step) ? 900_000_000 : 200_000_000
        watch.record([item(noisy, id: "noisy"), item(plateau, id: "plateau"), item(spike, id: "spike"), item(400_000_000, id: "flat")], at: t)
    }
    #expect(watch.findings().isEmpty)
}
@Test func leakWatchRejectsSawtoothGrowthThatKeepsDropping() {
    var watch = LeakWatch()
    for step in 0..<120 {
        let base: UInt64 = 200_000_000 + UInt64(step) * 1_000_000
        watch.record([item(step % 2 == 0 ? base : base - 60_000_000)], at: Double(step) * 20)
    }
    #expect(watch.findings().isEmpty)
}
@Test func leakWatchForgetsEverythingAcrossASleepGapAndDepartedOwners() {
    var watch = LeakWatch()
    var bytes: UInt64 = 20_000_000
    for step in 0..<80 { watch.record([item(bytes)], at: Double(step) * 10); bytes += 5_000_000 }
    #expect(watch.findings().count == 1)
    watch.record([item(bytes)], at: 800 + 3600) // the Mac slept for an hour
    #expect(watch.findings().isEmpty && watch.historySpan == 0)
    for tick in 1...6 { watch.record([item(bytes, id: "other")], at: 800 + 3600 + Double(tick) * 30) }
    #expect(watch.trackedCount == 1) // the owner absent for more than two minutes is forgotten
}
@Test func leakWatchMemoryIsBoundedByTheWindowNotByUptime() {
    var watch = LeakWatch()
    for step in 0..<20_000 { watch.record([item(100_000_000)], at: Double(step) * 30) } // ~7 days of closed-window ticks
    #expect(watch.historySpan <= 1800)
}
@Test func leakWatchIgnoresRepeatedOrBackwardsTimestamps() {
    var watch = LeakWatch()
    watch.record([item(1)], at: 100); watch.record([item(2)], at: 100); watch.record([item(3)], at: 50); watch.record([item(4)], at: 105)
    #expect(watch.historySpan == 0)
}
@Test func leakWatchSurvivesAnOwnerMissingFromOneReading() {
    var watch = LeakWatch()
    var bytes: UInt64 = 20_000_000
    for step in 0..<80 {
        let missing = step == 40 // one transient unreadable tick
        watch.record(missing ? [item(500_000_000, id: "steady")] : [item(bytes), item(500_000_000, id: "steady")], at: Double(step) * 10)
        bytes += 5_000_000
    }
    #expect(watch.findings().map(\.id) == ["python"])
}

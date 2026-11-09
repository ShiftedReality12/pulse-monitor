import Foundation
import Testing
@testable import PulseCore

private func record(_ store: inout TimelineStore, _ time: Double, pressure: UInt8 = 1, swap: UInt64? = 0, free: UInt64? = 100, thermal: UInt8 = 0, limit: Int? = nil) {
    store.record(time: time, pressure: pressure, swap: swap, compressed: 7, diskFree: free, thermal: thermal, speedLimit: limit)
}
@Test func pressureLevelsMapToTheKernelValuesAndUnknownIsNeverGreen() {
    #expect(Pressure.classify(1).level == 1)
    #expect(Pressure.classify(2).level == 2)
    #expect(Pressure.classify(4).level == 4)
    #expect(Pressure.classify(0).level == 0)
    #expect(Pressure.classify(3).level == 0)
    #expect(Pressure.classify(-1) == .unavailable)
}
@Test func timelineBucketsKeepTheWorstLevelAndLatestValues() {
    var store = TimelineStore()
    record(&store, 100, pressure: 1, swap: 10)
    record(&store, 110, pressure: 4, swap: 20, thermal: 2)
    record(&store, 119, pressure: 1, swap: 30, thermal: 0)
    #expect(store.count == 1)
    let sample = store.samples[0]
    #expect(sample.time == 90)
    #expect(sample.pressure == 4 && sample.thermal == 2 && sample.swap == 30)
    record(&store, 125, pressure: 2)
    #expect(store.count == 2)
    #expect(store.samples.map(\.time) == [90, 120])
}
@Test func timelineRingIsFixedSizeAndKeepsNewestInOrder() {
    var store = TimelineStore(capacity: 5)
    for index in 0..<50 { record(&store, Double(index) * 30, free: UInt64(index)) }
    #expect(store.count == 5)
    #expect(store.samples.map(\.diskFree) == [45, 46, 47, 48, 49])
}
@Test func twentyFourHoursOfBucketsIsBoundedAndSmall() {
    var store = TimelineStore()
    for index in 0..<(2880 * 3) { record(&store, Double(index) * 30) }
    #expect(store.count == 2880)
    #expect(store.samples.count * MemoryLayout<TimelineSample>.stride < 400_000)
}
@Test func reducingNeverLosesACriticalSpike() {
    var samples = (0..<1000).map { TimelineSample(time: Double($0) * 30, pressure: 1, swap: 0, compressed: 0, diskFree: 0, thermal: 0, speedLimit: nil) }
    samples[437].pressure = 4; samples[612].thermal = 3
    let reduced = TimelineSample.reduce(samples, limit: 240)
    #expect(reduced.count == 240)
    #expect(reduced.contains { $0.pressure == 4 } && reduced.contains { $0.thermal == 3 })
    #expect(reduced.first?.time ?? -1 >= 0 && reduced.last?.time == samples.last?.time)
}
@Test func throttlingEventsOpenAndCloseOnSeriousHeatOrASpeedLimit() {
    var store = TimelineStore()
    record(&store, 0, thermal: 0)
    record(&store, 30, thermal: 1) // fair is warm, not throttling
    #expect(store.events.isEmpty)
    record(&store, 60, thermal: 2)
    record(&store, 90, thermal: 3, limit: 70)
    #expect(store.events.count == 1 && store.events[0].end == nil)
    #expect(store.events[0].peak == 3 && store.events[0].lowestSpeedLimit == 70)
    record(&store, 120, thermal: 0, limit: 100)
    #expect(store.events[0].end == 120)
    record(&store, 150, thermal: 0, limit: 80) // a speed limit alone is throttling
    #expect(store.events.count == 2 && store.events[1].end == nil)
    #expect(store.events[0].summary.contains("critical") && store.events[0].summary.contains("70%"))
}
@Test func thermalUnknownNeverStartsAnEventAndEventsAreCapped() {
    var store = TimelineStore()
    record(&store, 0, thermal: TimelineSample.thermalUnknown)
    #expect(store.events.isEmpty)
    for index in 0..<120 { record(&store, Double(index) * 100, thermal: index % 2 == 0 ? 2 : 0) }
    #expect(store.events.count == TimelineStore.maximumEvents)
}
private func runwaySamples(hours: Double, startFree: Double, perHour: Double, step: Double = 30) -> [TimelineSample] {
    stride(from: 0.0, through: hours * 3600, by: step).map { t in
        TimelineSample(time: t, pressure: 1, swap: 0, compressed: 0, diskFree: UInt64(max(0, startFree + perHour * t / 3600)), thermal: 0, speedLimit: nil)
    }
}
@Test func runwayProjectsDaysToFullFromTheFittedFillRate() {
    let samples = runwaySamples(hours: 2, startFree: 20e9, perHour: -500e6)
    let estimate = DiskRunway.estimate(samples: samples, now: samples.last!.time)
    guard case let .shrinking(rate, days, five) = estimate.state else { Issue.record("expected shrinking, got \(estimate.state)"); return }
    #expect(abs(rate - 500e6) < 1e6)
    let expectedDays = (20e9 - 1e9) / 500e6 / 24
    #expect(abs(days - expectedDays) < 0.02)
    #expect(abs(five - (19e9 - 5e9) / 500e6 / 24) < 0.02)
    #expect(estimate.headline == "Full in about 2 days")
    #expect(estimate.free == UInt64(19e9))
}
@Test func runwayWithZeroFillRateIsStableNotADivisionByZero() {
    let samples = runwaySamples(hours: 1, startFree: 17e9, perHour: 0)
    let estimate = DiskRunway.estimate(samples: samples, now: samples.last!.time)
    #expect(estimate.state == .stable)
    #expect(estimate.headline.hasPrefix("Stable"))
    #expect(estimate.perHour == 0)
}
@Test func runwayNeedsTenMinutesAndHandlesDegenerateInput() {
    #expect(DiskRunway.estimate(samples: [], now: 0).state == .unavailable)
    let short = runwaySamples(hours: 0.1, startFree: 17e9, perHour: -1e9)
    guard case .measuring = DiskRunway.estimate(samples: short, now: short.last!.time).state else { Issue.record("expected measuring"); return }
    let one = [TimelineSample(time: 5, pressure: 1, swap: 0, compressed: 0, diskFree: 9, thermal: 0, speedLimit: nil)]
    guard case .measuring = DiskRunway.estimate(samples: one, now: 5).state else { Issue.record("expected measuring for one sample"); return }
    let unreadable = [TimelineSample(time: 0, pressure: 1, swap: 0, compressed: 0, diskFree: nil, thermal: 0, speedLimit: nil)]
    #expect(DiskRunway.estimate(samples: unreadable, now: 0).state == .unavailable)
}
@Test func runwayReportsGrowingAndTreatsAMultiYearBurnAsStable() {
    let growing = runwaySamples(hours: 1, startFree: 10e9, perHour: 2e9)
    guard case .growing = DiskRunway.estimate(samples: growing, now: growing.last!.time).state else { Issue.record("expected growing"); return }
    let tiny = runwaySamples(hours: 3, startFree: 400e9, perHour: -5e6)
    #expect(DiskRunway.estimate(samples: tiny, now: tiny.last!.time).state == .stable)
}
@Test func runwayIgnoresReadingsOlderThanSixHours() {
    let old = runwaySamples(hours: 7, startFree: 100e9, perHour: -10e9).map { var s = $0; s.time -= 20 * 3600; return s }
    let recent = runwaySamples(hours: 1, startFree: 17e9, perHour: 0).map { var s = $0; s.time += 7 * 3600; return s }
    let all = old + recent
    #expect(DiskRunway.estimate(samples: all, now: all.last!.time).state == .stable)
}
@Test func runwayWordsUseSingularForOneHourAndOneDay() {
    let hour = runwaySamples(hours: 1, startFree: 9e9, perHour: -4.2e9)
    #expect(DiskRunway.estimate(samples: hour, now: hour.last!.time).headline == "Full in about 1 hour")
    let soon = runwaySamples(hours: 1, startFree: 5.4e9, perHour: -4.2e9)
    #expect(DiskRunway.estimate(samples: soon, now: soon.last!.time).headline == "Full in under an hour")
    let day = runwaySamples(hours: 2, startFree: 21e9, perHour: -400e6)
    #expect(DiskRunway.estimate(samples: day, now: day.last!.time).headline == "Full in about 2 days")
}
@Test func aDiskWithNothingLeftSaysSoInsteadOfOneHour() {
    let samples = runwaySamples(hours: 1, startFree: 3e9, perHour: -3e9)
    let estimate = DiskRunway.estimate(samples: samples, now: samples.last!.time)
    #expect(estimate.free == 0 && estimate.headline == "Disk is full")
}
@Test func aWallClockThatMovesBackwardsRestartsTheTimelineInOrder() {
    var store = TimelineStore()
    for index in 0..<10 { record(&store, 10_000 + Double(index) * 30) }
    record(&store, 500)
    record(&store, 530)
    #expect(store.samples.map(\.time) == [480, 510])
    #expect(store.samples.map(\.time) == store.samples.map(\.time).sorted())
}
@Test func aFullDiskWithNoChangeStillSaysFull() {
    let samples = runwaySamples(hours: 1, startFree: 0, perHour: 0)
    #expect(DiskRunway.estimate(samples: samples, now: samples.last!.time).headline == "Disk is full")
}

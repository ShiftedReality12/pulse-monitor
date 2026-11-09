import Foundation
import Testing
@testable import PulseCore

@Test func footprintSeriesRetainsPeaksBetweenTwoSecondPoints() {
    var series = FootprintSeries(start: 0)
    series.observe(at: 0, bytes: 60_000_000)
    series.observe(at: 0.4, bytes: 120_000_000)
    for time in stride(from: 2.0, through: 60, by: 2) { series.observe(at: time, bytes: 60_000_000) }
    #expect(series.points.count == 30)
    #expect(series.points[0].bytes == 60_000_000)
    #expect(series.points[0].intervalPeak == 120_000_000)
    #expect(series.maximum == 120_000_000 && series.minimum == 60_000_000)
    #expect(series.skippedIntervals == 0)
}
@Test func footprintSeriesDoesNotInventMissingOrSkippedSamples() {
    var series = FootprintSeries(start: 0)
    series.observe(at: 2, bytes: nil)
    #expect(series.points.isEmpty && series.minimum == nil && series.missing == 1)
    series.observe(at: 6, bytes: 30_000_000)
    #expect(series.points.count == 1 && series.skippedIntervals == 2)
}

@Test func limitedTinyCPUNeverDisplaysMeaninglessLowerBoundZero() {
    var group = ProcessGroup(id: "owner", title: "owner", members: [1], resident: 569_000_000, cpu: 0.4, limited: true)
    for value in [0.0, 0.04, 0.4, 0.49] {
        group.cpu = value
        #expect(group.cpuSummary == nil)
        #expect(!group.compactMetrics.contains("%"))
        #expect(!group.why.contains("≥ 0%"))
        #expect(group.compactMetrics.contains("569 MB"))
    }
}
@Test func ownerCPULabelRetainsUsefulPrecisionAndUnavailableState() {
    var group = ProcessGroup(id: "owner", title: "owner", members: [1], resident: 40, cpu: 0.4, limited: false)
    #expect(group.cpuSummary == "0.4% CPU")
    group.cpu = 0.04; #expect(group.cpuSummary == "<0.1% CPU")
    group.cpu = 2.04; group.limited = true; #expect(group.cpuSummary == "2.0%+ CPU")
    group.cpu = 0.5; #expect(group.cpuSummary == "0.5%+ CPU")
    group.cpu = nil; #expect(group.cpuSummary == nil && group.why.contains("CPU unavailable"))
    group.cpu = .nan; #expect(group.cpuSummary == nil)
}

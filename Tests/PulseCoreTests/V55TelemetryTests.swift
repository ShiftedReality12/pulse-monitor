import Testing
@testable import PulseCore

@Test func footprintP95UsesNearestRankOfRealIntervalPeaks() {
    var series = FootprintSeries(start: 0)
    #expect(series.percentile95 == nil)
    for index in 1...30 {
        series.observe(at: Double(index) * 2 - 1, bytes: UInt64(index) * 1_000_000)
        series.observe(at: Double(index) * 2, bytes: 1)
    }
    #expect(series.points.count == 30)
    #expect(series.maximum == 30_000_000)
    #expect(series.percentile95 == 29_000_000)
    #expect(series.points.allSatisfy { $0.bytes == 1 })
}

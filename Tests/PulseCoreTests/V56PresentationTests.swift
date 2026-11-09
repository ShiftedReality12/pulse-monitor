import Foundation
import Testing
@testable import PulseCore

@Test func diskHeadroomBoundariesAndExplicitCalmExample() {
    for (free, expected) in [(9_999_999_999, DiskState.critical), (10_000_000_000, .warning),
                             (19_999_999_999, .warning), (20_000_000_000, .calm)] {
        #expect(DiskState.classify(free: UInt64(free), total: 100_000_000_000) == expected)
    }
    #expect(DiskState.classify(free: 32_600_000_000, total: 494_300_000_000) == .calm)
    #expect(DiskState.classify(free: 49_999_999_999, total: 1_000_000_000_000) == .critical)
    #expect(DiskState.classify(free: 50_000_000_000, total: 1_000_000_000_000) == .calm)
    #expect(DiskState.classify(free: nil, total: 100) == .unavailable)
    #expect(DiskState.classify(free: 101, total: 100) == .unavailable)
    #expect(DiskState.classify(free: 0, total: 0) == .unavailable)
}
@Test func humanHeroHasRealAmountsAndSuffixForPartialReadings() {
    var snapshot = healthySnapshot()
    snapshot.diskFree = 32_600_000_000; snapshot.diskTotal = 494_300_000_000
    var owner = ProcessGroup(id: "AI", title: "Claude Code · slate", members: [52], resident: 1_400_000_000, cpu: 3, limited: true)
    owner.category = "AI session"; snapshot.groups = [owner]
    var copy = HumanCopy(snapshot)
    #expect(copy.headline == "Your Mac is OK")
    #expect(copy.ownerLine == "Biggest user: Claude Code (slate), 1.4 GB+")
    #expect(copy.symbol == "checkmark.seal")
    snapshot.diskTotal = 100_000_000_000; snapshot.diskFree = 12_000_000_000; copy = HumanCopy(snapshot)
    #expect(copy.headline == "Disk is getting full: 12.0 GB left")
    snapshot.diskFree = 8_000_000_000; copy = HumanCopy(snapshot)
    #expect(copy.headline == "Disk is almost full: 8.0 GB left")
    for text in [copy.headline, copy.detail, copy.ownerLine] {
        #expect(!text.contains("≥") && !text.localizedCaseInsensitiveContains("observed"))
    }
}
@Test func traceGeometryUsesActualTimesAndKeepsSingleReadingExplicit() {
    let points = [PlotPoint(date: Date(timeIntervalSince1970: 0), value: 0),
                  PlotPoint(date: Date(timeIntervalSince1970: 5), value: 50),
                  PlotPoint(date: Date(timeIntervalSince1970: 20), value: 100)]
    let geometry = TraceGeometry.timeline(points, domain: 0...100)
    #expect(geometry.map(\.x) == [0, 0.25, 1])
    #expect(geometry.map(\.y) == [1, 0.5, 0])
    #expect(TraceGeometry.timeline([], domain: 0...100).isEmpty)
    #expect(TraceGeometry.timeline([points[1]], domain: 0...100).map(\.y) == [0.5, 0.5])
    #expect(TraceGeometry.readings([0, 10]).map(\.y) == [1, 0])
}

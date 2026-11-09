import Foundation
import Testing
@testable import PulseCore

private func owner(_ id: String, ram: UInt64, cpu: Double, writes: Double) -> ProcessGroup {
    var group = ProcessGroup(id: id, title: id, members: Array(1...(id == "AI" ? 15 : 1)).map(Int32.init), resident: ram, cpu: cpu, limited: false)
    group.hasVerifiedIdentity = true; group.writesPerSecond = writes; return group
}
@Test func reviewer50MBWriterRanksBelow2GBSession() {
    var ranking = ImpactRanking()
    let groups = [owner("daemon", ram: 40_000_000, cpu: 3, writes: 50_000_000), owner("AI", ram: 2_000_000_000, cpu: 3, writes: 0)]
    let ranked = ranking.rank(groups, totalMemory: 16_000_000_000, cores: 10, uptime: 0)
    #expect(ranked.first?.id == "AI")
    #expect(ranked[0].members.count == 15)
}
@Test func reviewerBurstFallsBelowSessionWithin30Seconds() {
    var ranking = ImpactRanking()
    var daemon = owner("daemon", ram: 40_000_000, cpu: 1000, writes: 50_000_000)
    let ai = owner("AI", ram: 2_000_000_000, cpu: 3, writes: 0)
    #expect(ranking.rank([daemon, ai], totalMemory: 16_000_000_000, cores: 10, uptime: 0).first?.id == "daemon")
    daemon.cpu = 3
    for time in stride(from: 6.0, through: 30.0, by: 6) {
        let ranked = ranking.rank([daemon, ai], totalMemory: 16_000_000_000, cores: 10, uptime: time)
        if time == 30 { #expect(ranked.first?.id == "AI") }
    }
}
@Test func sustained500MBWriterWith1GBStillRanksHigh() {
    var ranking = ImpactRanking()
    let ranked = ranking.rank([owner("writer", ram: 1_000_000_000, cpu: 3, writes: 500_000_000), owner("AI", ram: 2_000_000_000, cpu: 3, writes: 0)], totalMemory: 16_000_000_000, cores: 10, uptime: 0)
    #expect(ranked.first?.id == "writer")
}
@Test func normalizedTermsCapAndWritesNeverExceedFivePoints() {
    #expect(ImpactRanking.score(cpu: 1e10, memory: .max, writes: 1e15, totalMemory: 16_000_000_000, cores: 10) == 100)
    #expect(ImpactRanking.score(cpu: nil, memory: nil, writes: 1e15, totalMemory: 0, cores: 0) == 5)
    #expect(ImpactRanking.score(cpu: -10, memory: nil, writes: -10, totalMemory: 0, cores: 0) == 0)
}

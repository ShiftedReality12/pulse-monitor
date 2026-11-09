import Testing
@testable import PulseCore

@Test(arguments: [8, 16, 32, 64, 128])
func reviewer200MBWriterRanksBelow2GBSessionAtEveryCapacity(gigabytes: UInt64) {
    var daemon = ProcessGroup(id: "daemon", title: "daemon", members: [1], resident: 60_000_000, cpu: 3, limited: false)
    daemon.writesPerSecond = 200_000_000
    var ai = ProcessGroup(id: "AI", title: "AI", members: [2], resident: 2_000_000_000, cpu: 3, limited: false)
    ai.writesPerSecond = 0
    var ranking = ImpactRanking()
    let ranked = ranking.rank([daemon, ai], totalMemory: gigabytes * 1_000_000_000, cores: 10, uptime: 0)
    #expect(ranked.first?.id == "AI")
    #expect(ranked[0].impact > ranked[1].impact)
}

import Foundation
import Testing
@testable import PulseCore

private func hiddenOwner(name: String, path: String, ram: UInt64) -> ProcessGroup {
    Attribution.groups([ProcessSample(pid: 52, name: name, path: path, resident: ram, cpu: nil)])[0]
}
@Test func hiddenStartPID52CodexToClaudeDoesNotInheritState() {
    var ranking = ImpactRanking(), history = OwnerHistory()
    let old = hiddenOwner(name: "codex", path: "/bin/codex", ram: 4_000_000_000)
    var first = ranking.rank([old], totalMemory: 16_000_000_000, cores: 10, uptime: 0)
    history.apply(to: &first)
    let replacement = hiddenOwner(name: "claude", path: "/bin/claude", ram: 60_000_000)
    var second = ranking.rank([replacement], totalMemory: 16_000_000_000, cores: 10, uptime: 6)
    history.apply(to: &second)
    #expect(old.id != replacement.id)
    #expect(old.id.contains("/bin/codex") && replacement.id.contains("/bin/claude"))
    #expect(second[0].title == "Claude Code" && second[0].resident == 60_000_000)
    #expect(abs(second[0].impact - 0.20625) < 0.000001)
    #expect(second[0].memoryTrend == [60])
}
@Test func hiddenStartSameExecutableStillCannotProveContinuity() {
    var ranking = ImpactRanking(), history = OwnerHistory()
    for (time, ram) in [(0.0, UInt64(4_000_000_000)), (6, UInt64(60_000_000))] {
        var groups = ranking.rank([hiddenOwner(name: "codex", path: "/bin/codex", ram: ram)], totalMemory: 16_000_000_000, cores: 10, uptime: time)
        history.apply(to: &groups)
        if time == 6 {
            #expect(abs(groups[0].impact - 0.20625) < 0.000001)
            #expect(groups[0].memoryTrend == [60])
        }
    }
}
@Test func hiddenPathsUseNamesInUnknownStartKeys() {
    let codex = hiddenOwner(name: "codex", path: "", ram: 1)
    let claude = hiddenOwner(name: "claude", path: "", ram: 1)
    #expect(codex.id != claude.id)
    let a = hiddenOwner(name: "helper-a", path: "", ram: 1)
    let b = hiddenOwner(name: "helper-b", path: "", ram: 1)
    #expect(a.id != b.id)
}
@Test func verifiedStartRetainsSmoothingAndHistoryThroughActualAttribution() {
    var ranking = ImpactRanking(), history = OwnerHistory()
    for (time, ram) in [(0.0, UInt64(4_000_000_000)), (6, UInt64(60_000_000))] {
        let process = ProcessSample(pid: 52, identity: 100, name: "codex", path: "/bin/codex", resident: ram, cpu: nil)
        var groups = ranking.rank(Attribution.groups([process]), totalMemory: 16_000_000_000, cores: 10, uptime: time)
        history.apply(to: &groups)
        if time == 6 {
            #expect(groups[0].impact > 0.20625)
            #expect(groups[0].memoryTrend == [4000, 60])
        }
    }
}

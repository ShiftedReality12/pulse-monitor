import Testing
import Foundation
@testable import PulseCore

@Test func heatBandsAndThermalOverride() {
    for (value, expected) in [(69.99, HeatLevel.cool), (70, .warm), (84, .warm), (84.99, .warm), (85, .hot), (94.99, .hot), (95, .risk)] {
        #expect(HeatLevel.classify(temperature: value, thermal: "Nominal") == expected)
    }
    #expect(HeatLevel.classify(temperature: 40, thermal: "Serious") == .risk)
    #expect(HeatLevel.classify(temperature: nil, thermal: "Critical") == .risk)
    #expect(HeatLevel.classify(temperature: nil, thermal: "Nominal") == .unavailable)
    var snapshot = Snapshot(); snapshot.temperature = 84; snapshot.cpuDieTemperature = 96
    #expect(snapshot.heatLevel == .risk)
    #expect(snapshot.signal == .heat)
}
@Test func ringBoundsOrderAndDownsampling() {
    var ring = NumericHistory(capacity: 1801)
    for index in 0..<10_000 {
        var sample = Snapshot(); sample.date = Date(timeIntervalSince1970: Double(index * 2)); sample.cpu = index == 9_500 ? 100 : 10
        ring.append(HistorySample(sample))
    }
    #expect(ring.count == 1801)
    let points = ring.points(\.cpu)
    #expect(points.count <= 120)
    #expect(points.first?.date == Date(timeIntervalSince1970: 16_398))
    #expect(points.last?.date == Date(timeIntervalSince1970: 19_998))
    #expect(points.contains { $0.value == 100 })
    #expect(zip(points, points.dropFirst()).allSatisfy { $0.date < $1.date })
    #expect(Set(points.map(\.date)).count == points.count)
}
@Test func ringDropsExpiredAndMissingMetrics() {
    var ring = NumericHistory(capacity: 3)
    var s = Snapshot(); s.date = Date(timeIntervalSince1970: 0); s.cpu = 1; ring.append(HistorySample(s))
    s.date = Date(timeIntervalSince1970: 4000); s.cpu = nil; ring.append(HistorySample(s))
    #expect(ring.points(\.cpu).isEmpty)
    s.date = Date(timeIntervalSince1970: 4002); s.cpu = 5; ring.append(HistorySample(s))
    #expect(ring.points(\.cpu).map(\.value) == [5])
}
@Test func adaptiveCadenceAndTolerance() {
    #expect(SamplingPolicy.interval(visible: false) >= 5)
    #expect((1...2).contains(SamplingPolicy.interval(visible: true)))
    #expect(SamplingPolicy.processInterval(visible: false) >= 30)
    #expect(SamplingPolicy.processInterval(visible: true) == 6)
    #expect(SamplingPolicy.leeway(visible: false) == 1)
}
private func fixture(_ pid: Int32, parent: Int32, name: String, ram: UInt64, cpu: Double, cwd: String? = nil, path: String = "") -> ProcessSample {
    var result = ProcessSample(pid: pid, identity: UInt64(pid) * 100, name: name, path: path, resident: ram, cpu: cpu)
    result.parent = parent; result.cwd = cwd; result.writesPerSecond = 0; return result
}
@Test func attributionRollsChildToolsIntoRealSessionOwner() {
    let groups = Attribution.groups([
        fixture(10, parent: 1, name: "Terminal", ram: 20, cpu: 0, path: "/Applications/Terminal.app/Contents/MacOS/Terminal"),
        fixture(20, parent: 10, name: "zsh", ram: 10, cpu: 0),
        fixture(30, parent: 20, name: "codex", ram: 1_000_000_000, cpu: 1, cwd: "/work/my-project"),
        fixture(31, parent: 30, name: "node", ram: 500_000_000, cpu: 1),
        fixture(32, parent: 31, name: "python", ram: 500_000_000, cpu: 1),
        fixture(40, parent: 1, name: "mediaanalysisd", ram: 20_000_000, cpu: 3)
    ])
    let session = groups.first { $0.category == "AI session" }
    #expect(session?.title == "Codex · my-project")
    #expect(session?.members == [30, 31, 32])
    #expect(session?.resident == 2_000_000_000)
    #expect(session?.launcher == "Terminal")
    #expect(session?.cwd == "/work/my-project")
    #expect(session?.aiProcessCount == 1)
    #expect(groups.reduce(0) { $0 + $1.members.count } == 6)
    var ranking = ImpactRanking()
    let ranked = ranking.rank(groups, totalMemory: 16_000_000_000, cores: 10, uptime: 0)
    #expect(ranked.first?.id == session?.id) // 3% daemon must not outrank this 2 GB session.
}
@Test func attributionRejectsReusedParentsAndHandlesCyclesDenials() {
    var oldChild = fixture(1, parent: 9, name: "python", ram: 10, cpu: 1)
    oldChild.identity = 1
    var reused = fixture(9, parent: 1, name: "codex", ram: 10, cpu: 1)
    reused.identity = 100
    let groups = Attribution.groups([oldChild, reused])
    #expect(!groups.first(where: { $0.category == "AI session" })!.members.contains(1))
    let denied = ProcessSample(pid: 50, name: "", resident: nil, cpu: nil)
    let unknown = Attribution.groups([denied])[0]
    #expect(unknown.title == "Unknown helper (pid 50)")
    #expect(unknown.cwd == nil && unknown.resident == nil && unknown.launcher == nil)
    #expect(unknown.category == "Unknown")
    var cycleA = fixture(60, parent: 61, name: "node", ram: 10, cpu: 1)
    var cycleB = fixture(61, parent: 60, name: "python", ram: 10, cpu: 1)
    cycleA.identity = 0; cycleB.identity = 0
    #expect(Attribution.groups([cycleA, cycleB]).reduce(0) { $0 + $1.members.count } == 2)
}
@Test func impactWeightsAndRollingRecovery() {
    #expect(abs(ImpactRanking.score(cpu: 1000, memory: 16_000_000_000, writes: 500_000_000, totalMemory: 16_000_000_000, cores: 10) - 100) < 0.00001)
    var group = ProcessGroup(id: "owner", title: "owner", members: [1], resident: 0, cpu: 1000, limited: false)
    group.hasVerifiedIdentity = true
    var ranking = ImpactRanking()
    let initial = ranking.rank([group], totalMemory: 1000, cores: 10, uptime: 0)[0].impact
    group.cpu = 0
    let later = ranking.rank([group], totalMemory: 1000, cores: 10, uptime: 60)[0].impact
    #expect(abs(later - initial * exp(-10)) < 0.00001)
    #expect(ranking.rank([], totalMemory: 1000, cores: 10, uptime: 120).isEmpty)
}
@Test func dictionaryCoversCommonFixtureAndHonestFallback() {
    let fixture = "mediaanalysisd photoanalysisd photolibraryd cloudphotod mds mds_stores mdworker mdworker_shared corespotlightd WindowServer kernel_task launchd logd syslogd sysmond configd powerd runningboardd notifyd distnoted cfprefsd trustd securityd secd tccd authd opendirectoryd accountsd loginwindow SystemUIServer ControlCenter Finder Dock Safari sharingd rapportd bluetoothd bluetoothuserd airportd wifid mDNSResponder locationd timed ntpd coreaudiod coreduetd duetexpertd suggestd bird cloudd fileproviderd filecoordinationd nsurlsessiond apsd usernoted NotificationCenter backupd backupd-helper fseventsd diskarbitrationd diskmanagementd storagekitd softwareupdated installd appstoreagent kernelmanagerd iconservicesagent iconservicesd fontd pkd sandboxd usbd syspolicyd Terminal Python node git Codex".split(separator: " ").map(String.init)
    #expect(fixture.count >= 60)
    #expect(ProcessDictionary.entries.count >= 60)
    for name in fixture { #expect(ProcessDictionary.entries[name] != nil) }
    #expect(ProcessDictionary.details(name: "mediaanalysisd").what.contains("photo"))
    #expect(ProcessDictionary.details(name: "mystery", path: "/usr/local/bin/mystery").what.contains("Purpose is not yet identified"))
}

@Test func versionNamedClaudeStillOwnsItsTools() {
    let groups = Attribution.groups([
        fixture(10, parent: 1, name: "Terminal", ram: 10, cpu: 0),
        fixture(20, parent: 10, name: "2.1.312", ram: 2_000_000_000, cpu: 2, cwd: "/work/project", path: "/home/example/.local/share/claude/versions/2.1.312"),
        fixture(21, parent: 20, name: "node", ram: 10, cpu: 1)
    ])
    let owner = groups.first { $0.category == "AI session" }
    #expect(owner?.title == "Claude Code · project")
    #expect(owner?.members == [20, 21])
    #expect(owner?.launcher == "Terminal")
    #expect(owner?.aiProcessCount == 1)
}

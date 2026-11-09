import Foundation
import Testing
@testable import PulseCore

@Test func demoFlagReadsOnlyExactOne() {
    #expect(PulseEnvironment.demoEnabled(["PULSE_DEMO": "1"]))
    #expect(!PulseEnvironment.demoEnabled([:]))
    #expect(!PulseEnvironment.demoEnabled(["PULSE_DEMO": "true"]))
    #expect(!PulseEnvironment.demoEnabled(["PULSE_DEMO": "0"]))
}

@Test func demoAnonymizeRewritesLiveSessionLabelsAndFillsGaps() {
    var live = ProcessSample(pid: 21, identity: 200, name: "claude", path: "/opt/tools/claude", resident: 400_000_000, cpu: 3)
    live.cwd = "/Users/example/secret-repo"
    live.configDir = "/Users/example/.claude-private"
    live.pane = "live-secret-pane"
    live.agentEnvironmentRead = true
    let groups = Attribution.groups([live])
    let scrubbed = DemoData.anonymizeGroups(groups)
    let sessions = scrubbed.filter { $0.category == "AI session" }
    #expect(sessions.count >= 2)
    #expect(sessions.allSatisfy { $0.pane?.hasPrefix("demo-pane-") == true })
    #expect(sessions.allSatisfy { $0.cwd?.hasPrefix("/home/demo/") == true })
    #expect(sessions.allSatisfy { $0.configHome?.hasPrefix("~/Account ") == true })
    #expect(sessions.allSatisfy { !($0.pane?.contains(":") ?? false) || $0.pane?.hasPrefix("demo-pane-") == true })
    #expect(sessions.allSatisfy { !($0.title.contains("secret-repo") || ($0.cwd?.contains("secret-repo") ?? false)) })
    #expect(sessions.contains { $0.title.contains("project-a") })
}

@Test func demoUsageTextParsesGenericAccountsOnly() {
    let accounts = UsageReport.parse(DemoData.usageSwiftBar)
    #expect(accounts.map(\.name) == ["Account A", "Account B"])
    #expect(accounts[0].windows.first?.usedPercent == 30)
    #expect(accounts.allSatisfy { !$0.name.lowercased().contains("claude") })
}

@Test func demoTimelineSeedHasLengthAndSwapCompressedVariation() {
    let samples = DemoData.timelineSeed(endingAt: 1_700_000_000, bucketCount: 120)
    #expect(samples.count >= 2)
    #expect(samples.count == 120)
    let swaps = Set(samples.compactMap(\.swap))
    let compressed = Set(samples.compactMap(\.compressed))
    #expect(swaps.count >= 2)
    #expect(compressed.count >= 2)
    #expect(samples.contains { $0.pressure == 1 })
    #expect(samples.contains { $0.pressure == 2 })
    var store = TimelineStore()
    store.preload(samples)
    #expect(store.samples.count >= 2)
    #expect(Set(store.samples.compactMap(\.swap)).count >= 2)
    #expect(Set(store.samples.compactMap(\.compressed)).count >= 2)
}

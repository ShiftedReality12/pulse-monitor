import Foundation
import Testing
@testable import PulseCore
@testable import PulseApp

@Test func drilldownRanksActualCombinedOwnersAndSwitchesMetricWithStableTies() throws {
    let owners = Attribution.groups([
        ProcessSample(pid: 1, name: "one", path: "/bin/one", resident: 50, cpu: 1),
        ProcessSample(pid: 2, name: "one", path: "/bin/one", resident: 60, cpu: 2),
        ProcessSample(pid: 3, name: "two", path: "/bin/two", resident: 100, cpu: 9)
    ])
    let memory = ProcessMetric.memory.ranked(owners)
    #expect(memory.first?.members == [1, 2] && memory.first?.resident == 110)
    #expect(ProcessMetric.cpu.ranked(owners).first?.members == [3])
    var a = try #require(memory.first), b = a
    a.id = "a"; b.id = "b"
    for metric in ProcessMetric.allCases { #expect(metric.ranked([b, a]).map(\.id) == ["a", "b"]) }
    #expect(DetailDestination(arguments: ["--show-window", "--show-drilldown", "memory"]) == .processes(.memory))
    #expect(DetailDestination(arguments: ["--show-window", "--show-drilldown", "cpu"]) == .processes(.cpu))
    #expect(DetailDestination(arguments: ["--show-drilldown", "memory"]) == nil)
}
@Test func keyedHistoryIsBoundedPrunesVanishedGroupsAndKeepsOnlyTheLastMinute() {
    var history = KeyedRingBuffer<String, Double>(capacity: 60, horizon: 60)
    for index in 0..<120 { history.record(["a": Double(index), "b": 2], at: Double(index)) }
    #expect(history.samples(for: "a", at: 119).count == 60)
    #expect(history.samples(for: "a", at: 119).first?.value == 60)
    history.record(["a": 120], at: 120)
    #expect(history.keys == Set(["a"]))
    #expect(history.samples(for: "b", at: 120).isEmpty)
    #expect(history.samples(for: "a", at: 181).isEmpty)
}
@MainActor @Test func drilldownHistoryExistsOnlyWhileOpenAndUsesAtMostTwelveOwners() {
    let model = ProcessDrilldownModel()
    let groups = (0..<40).map { ProcessGroup(id: "g\($0)", title: "g\($0)", members: [], resident: UInt64($0), cpu: Double(40 - $0), limited: false) }
    let date = Date(timeIntervalSince1970: 100)
    model.record(groups: groups, sampledAt: date)
    #expect(model.history.keys.isEmpty)
    model.open(.memory)
    model.record(groups: groups, sampledAt: date)
    #expect(model.history.keys.count == 12)
    #expect(model.history.samples(for: "g39", at: 100).count == 1)
    model.open(.cpu)
    model.record(groups: groups, sampledAt: date)
    #expect(model.history.samples(for: "g0", at: 100).count == 1)
    model.close()
    #expect(model.history.keys.isEmpty)
    model.record(groups: groups, sampledAt: date.addingTimeInterval(2))
    #expect(model.history.keys.isEmpty)
}

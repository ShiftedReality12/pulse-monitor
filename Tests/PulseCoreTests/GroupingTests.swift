import Testing
import Foundation
@testable import PulseCore

@Test func friendlyGroupingSeparatesBundlesAndFallsBackHonestly() {
    let groups = Attribution.groups([
        ProcessSample(pid: 1, name: "Python", path: "/usr/local/Python.app/Contents/MacOS/Python", resident: 10, cpu: 3),
        ProcessSample(pid: 2, name: "Python", path: "/other/Python.app/Contents/MacOS/Python", resident: 20, cpu: 4),
        ProcessSample(pid: 3, name: "Process 3", path: "/usr/bin/日本 helper", resident: 1, cpu: 0),
        ProcessSample(pid: 4, name: "", resident: nil, cpu: nil),
        ProcessSample(pid: 5, name: "claude", path: "/bin/claude", resident: 4, cpu: 1),
        ProcessSample(pid: 6, name: "codex", path: "/bin/codex", resident: 5, cpu: 2)
    ])
    #expect(groups.count == 6)
    let python = groups.first { $0.id == "app:/other/Python.app" }!
    #expect(python.title == "Python")
    #expect(python.cpu == 4)
    #expect(python.resident == 20)
    #expect(python.members == [2])
    #expect(groups.contains { $0.title == "Claude Code" })
    #expect(groups.contains { $0.title == "Codex" })
    #expect(groups.contains { $0.title == "日本 helper" })
    #expect(groups.contains { $0.title == "Unknown helper (pid 4)" && $0.resident == nil })
    #expect(!groups.contains { $0.title.hasPrefix("Process ") })
}

@Test func unchangedReadingsIgnoreCaptureTimes() {
    var first = healthySnapshot(), second = first
    first.date = Date(timeIntervalSince1970: 0); second.date = Date(timeIntervalSince1970: 2)
    second.sensorSampleDate = second.date; second.processSampleDate = second.date
    #expect(first.hasSameReadings(as: second))
    second.cpu = 21; #expect(!first.hasSameReadings(as: second))
    #expect(HistorySample(first).temperature == 65)
    #expect(HistorySample(first).thermalSeverity == 0)
    second.temperature = 65; second.sensorSampleDate = first.date
    #expect(HistorySample(second).temperature == nil) // Cached sensor values are not new measurements.
    second.sensorSampleDate = second.date
    #expect(HistorySample(second).temperature == 65)
}

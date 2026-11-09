import Foundation
import Observation
import PulseCore

enum DetailDestination: Equatable {
    case processes(ProcessMetric)
    init?(arguments: [String]) {
        guard arguments.contains("--show-window"), let index = arguments.firstIndex(of: "--show-drilldown"),
              arguments.indices.contains(index + 1), let metric = ProcessMetric(rawValue: arguments[index + 1]) else { return nil }
        self = .processes(metric)
    }
}
@MainActor @Observable final class ProcessDrilldownModel {
    private(set) var metric: ProcessMetric?
    private(set) var history = KeyedRingBuffer<String, Double>(capacity: 60, horizon: 60)
    private(set) var sampledAt: Date?
    private var retainedUntil: [String: Date] = [:]
    private var displayed: Set<String> = []
    var isOpen: Bool { metric != nil }
    func open(_ metric: ProcessMetric) {
        guard self.metric != metric else { return }
        close(); self.metric = metric
    }
    func close() {
        metric = nil; sampledAt = nil; retainedUntil = [:]; displayed = []
        history = KeyedRingBuffer(capacity: 60, horizon: 60)
    }
    func record(groups: [ProcessGroup], sampledAt: Date?) {
        guard let metric, let sampledAt, sampledAt != self.sampledAt else { return }
        self.sampledAt = sampledAt
        let top = Array(metric.ranked(groups).prefix(12))
        let previous = displayed
        displayed = Set(top.map(\.id))
        for key in previous.subtracting(displayed) { retainedUntil[key] = sampledAt.addingTimeInterval(60) }
        for key in displayed { retainedUntil[key] = sampledAt.addingTimeInterval(60) }
        let held = history.keys.filter { !displayed.contains($0) && (retainedUntil[$0] ?? .distantPast) > sampledAt }
            .sorted { retainedUntil[$0] == retainedUntil[$1] ? $0 < $1 : retainedUntil[$0]! > retainedUntil[$1]! }.prefix(12)
        let keep = displayed.union(held)
        retainedUntil = retainedUntil.filter { keep.contains($0.key) }
        let values = groups.filter { keep.contains($0.id) }.compactMap { group in metric.value(group).map { (group.id, $0) } }
        history.record(Dictionary(uniqueKeysWithValues: values), at: sampledAt.timeIntervalSince1970, retaining: keep)
    }
    var trends: [String: [PlotPoint]] {
        guard let sampledAt else { return [:] }
        return Dictionary(uniqueKeysWithValues: displayed.map { key in
            (key, history.samples(for: key, at: sampledAt.timeIntervalSince1970).map {
                PlotPoint(date: Date(timeIntervalSince1970: $0.time), value: $0.value)
            })
        })
    }
}

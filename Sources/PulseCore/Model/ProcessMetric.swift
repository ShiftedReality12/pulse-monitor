import Foundation

public enum ProcessMetric: String, CaseIterable, Sendable {
    case memory, cpu
    public var label: String { self == .memory ? "Memory" : "CPU" }
    public func value(_ group: ProcessGroup) -> Double? {
        let value = self == .memory ? group.resident.map(Double.init) : group.cpu
        return value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
    public func ranked(_ groups: [ProcessGroup]) -> [ProcessGroup] {
        groups.sorted {
            let a = value($0) ?? -1, b = value($1) ?? -1
            return a == b ? $0.id < $1.id : a > b
        }
    }
}

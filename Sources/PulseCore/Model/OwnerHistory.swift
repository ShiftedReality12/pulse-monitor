import Foundation

/// Numeric current-owner trends only, at most 30 process refreshes per extant owner.
struct OwnerHistory {
    private var values: [String: [Double]] = [:]
    mutating func apply(to groups: inout [ProcessGroup]) {
        var next: [String: [Double]] = [:]
        for index in groups.indices {
            let group = groups[index]
            var trend = group.hasVerifiedIdentity ? values[group.id] ?? [] : []
            if let memory = group.resident { trend.append(Double(memory) / 1e6) }
            if trend.count > 30 { trend.removeFirst(trend.count - 30) }
            groups[index].memoryTrend = trend
            if group.hasVerifiedIdentity { next[group.id] = trend }
        }
        values = next
    }
}

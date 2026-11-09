import Foundation
import PulseCore

/// What the window actually draws. Sensor noise below that text does not count as a new frame.
enum ScreenSignature: Equatable {
    static func token(snapshot: Snapshot, plots: PlotHistory, insights: Insights) -> String {
        let copy = HumanCopy(snapshot)
        var lines = [copy.headline, copy.ownerLine, copy.symbol, copy.detail]
        lines.append(MetricFormat.percent(snapshot.memoryPercent))
        lines.append(snapshot.cpu.map { String(Int($0.rounded())) } ?? "-")
        lines.append(snapshot.effectiveTemperature.map { String(Int($0.rounded())) } ?? "-")
        lines.append(snapshot.thermal)
        lines.append(snapshot.pressure.rawValue)
        lines.append(MetricFormat.bytes(snapshot.swap))
        lines.append(MetricFormat.bytes(snapshot.compressed))
        lines.append(MetricFormat.bytes(snapshot.memoryUsed))
        lines.append(MetricFormat.bytes(snapshot.diskFree))
        lines.append(MetricFormat.bytes(snapshot.diskTotal))
        lines.append(MetricFormat.bytes(snapshot.bytesWritten))
        lines.append(MetricFormat.bytes(snapshot.writtenToday))
        lines.append(snapshot.baselineStatus)
        lines.append(snapshot.fans.max().map { String(Int($0.rounded())) } ?? "-")
        lines.append(snapshot.cpuSpeedLimit.map(String.init) ?? "-")
        lines.append(snapshot.thermalWarning.map(String.init) ?? "-")
        lines.append(snapshot.sensorStatus)
        lines.append(snapshot.topMemoryGroup ?? "-")
        lines.append("groups:\(snapshot.groups.count):\(snapshot.limitedProcessCount)")
        for group in snapshot.groups.prefix(8) {
            let cpu = group.cpu.map { String(Int($0.rounded())) } ?? "-"
            let impact = String(format: "%.1f", group.impact)
            lines.append("\(group.id)|\(group.title)|\(group.memoryLabel)|\(cpu)|\(impact)|\(group.compactMetrics)|\(group.members.count)|\(group.pane ?? "")|\(group.configHome ?? "")")
        }
        var rest = snapshot.groups.count
        for group in snapshot.groups.dropFirst(8) {
            rest = rest &* 33 &+ Int((group.resident ?? 0) / 1_000_000)
            rest = rest &* 33 &+ Int((group.cpu ?? -1).rounded())
        }
        lines.append("rest:\(rest)")
        // The plotted line is one hour wide; a new 30-second bucket is the visible step.
        lines.append("chart:\(bucket(plots.cpu)):\(Int((plots.cpu.last?.value ?? -1).rounded())):\(bucket(plots.memory)):\(Int((plots.memory.last?.value ?? -1).rounded())):\(bucket(plots.disk)):\(bucket(plots.temperature))")
        lines.append(insights.leaks.map(\.explanation).joined(separator: " • "))
        lines.append(insights.runway.headline)
        lines.append(insights.runway.detail)
        lines.append(insights.events.last?.summary ?? "")
        lines.append("leaks:\(insights.leakTracked)")
        return lines.joined(separator: "\n")
    }
    private static func bucket(_ points: [PlotPoint]) -> Int {
        points.last.map { Int($0.date.timeIntervalSince1970 / 30) } ?? 0
    }
}

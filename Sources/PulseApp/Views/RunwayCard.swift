import SwiftUI
import PulseCore

/// Free space, fill rate and projected runway for the startup disk (F4).
struct RunwayCard: View {
    let snapshot: Snapshot
    let insights: Insights
    var body: some View {
        let runway = insights.runway
        let recent = insights.timeline.filter { $0.time >= (insights.timeline.last?.time ?? 0) - DiskRunway.window }
        let points = TimelineSample.reduce(recent, limit: 240).compactMap { sample in
            sample.diskFree.map { PlotPoint(date: Date(timeIntervalSince1970: sample.time), value: Double($0)) }
        }
        VStack(alignment: .leading, spacing: 12) {
            Label("Disk runway", systemImage: "gauge.with.needle").font(.headline).foregroundStyle(.secondary)
            Text(runway.headline).font(.system(.title, design: .rounded, weight: .semibold))
            Text(runway.detail).foregroundStyle(.secondary)
            HStack(spacing: 28) {
                LabeledContent("Free now", value: MetricFormat.bytes(snapshot.diskFree))
                LabeledContent("Fill rate", value: rate(runway))
                LabeledContent("Based on", value: runway.basedOn > 0 ? (runway.basedOn >= 3600 ? String(format: "%.1f h", runway.basedOn / 3600) : "\(Int(runway.basedOn / 60)) min") : "—")
            }.monospacedDigit()
            TimelineLine(title: "Free space", points: points, tint: snapshot.diskTone.color, format: { MetricFormat.bytes(UInt64(max(0, $0))) })
            Text("A straight line fitted to the last six hours of free-space readings. Temporary files and cache cleanups can move it; treat the date as a guide, not a promise.")
                .font(.caption).foregroundStyle(.secondary)
        }.modifier(ContentCard())
    }
    private func rate(_ runway: RunwayEstimate) -> String {
        guard let perHour = runway.perHour else { return "Measuring" }
        if perHour == 0 { return "0 MB/hour" }
        let value = abs(perHour)
        let text = value >= 1e9 ? String(format: "%.1f GB/hour", value / 1e9) : String(format: "%.0f MB/hour", value / 1e6)
        return (perHour < 0 ? "−" : "+") + text
    }
}

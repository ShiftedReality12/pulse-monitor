import SwiftUI
import PulseCore

/// Heat, macOS thermal state and throttling events (F5).
struct HeatSection: View {
    let snapshot: Snapshot
    let plots: PlotHistory
    var insights = Insights()
    @State private var range = TimelineRange.six
    var body: some View {
        let samples = range.samples(insights.timeline)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.heatLevel.rawValue).font(.largeTitle.weight(.semibold)).foregroundStyle(snapshot.heatTone.color)
                    Spacer()
                    RangePicker(range: $range)
                }
                Text("macOS thermal state: \(snapshot.thermal.lowercased())").foregroundStyle(.secondary)
                Text(snapshot.effectiveTemperature.map { String(format: "%.1f°C", $0) } ?? "Sensor unavailable").font(.title.monospacedDigit())
                HeatBar(temperature: snapshot.effectiveTemperature)
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Thermal state", value: snapshot.thermal)
                    LabeledContent("CPU speed limit", value: snapshot.cpuSpeedLimit.map { $0 >= 100 ? "None (100%)" : "Limited to \($0)%" } ?? "None recorded")
                    LabeledContent("Thermal warning level", value: snapshot.thermalWarning.map { $0 == 0 ? "None" : "Level \($0)" } ?? "None recorded")
                    LabeledContent("Fans", value: snapshot.fans.isEmpty ? "Not reported on this Mac" : snapshot.fans.map { String(format: "%.0f rpm", $0) }.joined(separator: ", "))
                }.modifier(ContentCard())
                LevelBand(title: "Thermal state over time", samples: samples, level: \.thermal, color: thermalColor,
                          legend: [("Nominal", .green), ("Warm", .yellow), ("Serious", .orange), ("Critical", .red)]).modifier(ContentCard())
                VStack(alignment: .leading, spacing: 10) {
                    Text("Throttling events").font(.headline)
                    if insights.events.isEmpty {
                        Text("None since Pulse started" + (insights.startedAt.map { " at " + Date(timeIntervalSince1970: $0).formatted(date: .omitted, time: .shortened) } ?? "") + ". macOS has not slowed this Mac to cool it.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(insights.events.reversed()) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Date(timeIntervalSince1970: event.start).formatted(date: .abbreviated, time: .standard) + " – " + (event.end.map { Date(timeIntervalSince1970: $0).formatted(date: .omitted, time: .standard) } ?? "still happening")).font(.callout.weight(.semibold))
                            Text(event.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.modifier(ContentCard())
                if snapshot.effectiveTemperature != nil {
                    HistoryChart(points: plots.temperature, domain: 0...150, axes: true).frame(height: 140)
                }
                Text(Vital.heat.explanation(snapshot)).font(.callout).foregroundStyle(.secondary)
                Text("A throttling event means macOS reported serious or critical heat, or limited the CPU speed. Fair (Warm) is not counted. Events are kept in memory until Pulse quits.").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
}

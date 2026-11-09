import SwiftUI
import PulseCore

/// Memory pressure level, swap and compressed memory over time (F3).
struct MemorySection: View {
    let monitor: Monitor
    @State private var range = TimelineRange.hour
    var body: some View {
        let _ = monitor.renderToken
        let snapshot = monitor.snapshot
        let samples = range.samples(monitor.insights.timeline)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Memory pressure").font(.largeTitle.weight(.semibold))
                    Spacer()
                    RangePicker(range: $range)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Circle().fill(pressureColor(snapshot.pressure.level)).frame(width: 14, height: 14)
                        Text("\(snapshot.pressure.rawValue) pressure").font(.title2.weight(.semibold))
                        Text("(macOS level \(snapshot.pressure.level))").font(.callout).foregroundStyle(.secondary)
                    }
                    Text(Self.explanation(snapshot.pressure)).foregroundStyle(.secondary)
                    HStack(spacing: 28) {
                        LabeledContent("Swap used", value: MetricFormat.bytes(snapshot.swap))
                        LabeledContent("Compressed", value: MetricFormat.bytes(snapshot.compressed))
                        LabeledContent("Memory used", value: MetricFormat.bytes(snapshot.memoryUsed))
                    }.monospacedDigit()
                }.modifier(ContentCard())
                LevelBand(title: "Pressure level", samples: samples, level: \.pressure, color: pressureColor,
                          legend: [("Normal", .green), ("Tight", .yellow), ("Critical", .red)]).modifier(ContentCard())
                TimelineLine(title: "Swap used", points: samples.compactMap(\.swapPoint), tint: .orange, format: { MetricFormat.bytes(UInt64(max(0, $0))) }).modifier(ContentCard())
                TimelineLine(title: "Compressed memory", points: samples.compactMap { sample in
                    sample.compressed.map { PlotPoint(date: Date(timeIntervalSince1970: sample.time), value: Double($0)) }
                }, tint: .blue, format: { MetricFormat.bytes(UInt64(max(0, $0))) }).modifier(ContentCard())
                Text("Readings are kept in memory for 24 hours in 30-second steps and are lost when Pulse quits. Each step shows the worst pressure level seen in it.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
    static func explanation(_ pressure: Pressure) -> String {
        switch pressure {
        case .normal: "macOS has enough memory. Swap that is already used does not mean trouble right now."
        case .warning: "Memory is tight. macOS is compressing and swapping to keep up; apps may feel slower."
        case .critical: "Memory is critically low. Quit big apps or AI sessions to avoid freezes."
        case .unavailable: "macOS did not report a pressure level."
        }
    }
}

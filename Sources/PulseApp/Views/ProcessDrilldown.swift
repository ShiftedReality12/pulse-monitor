import SwiftUI
import PulseCore

struct ProcessDrilldown: View {
    let monitor: Monitor
    let back: () -> Void
    private var model: ProcessDrilldownModel { monitor.drilldown }
    var body: some View {
        let _ = monitor.renderToken
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: back) { Label("Back", systemImage: "chevron.left") }.keyboardShortcut(.cancelAction)
                Text("Processes by \(model.metric?.label ?? "Memory")").font(.title2.weight(.semibold))
                Spacer()
                Picker("Metric", selection: Binding(get: { model.metric ?? .memory }, set: {
                    model.open($0); model.record(groups: monitor.snapshot.groups, sampledAt: monitor.snapshot.processSampleDate)
                })) {
                    ForEach(ProcessMetric.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).frame(width: 180)
            }.padding(.horizontal, 24).padding(.top, 20)
            Text("Combined owner use · last 60 seconds for the top 12 · Memory is summed physical footprint, the same figure as Activity Monitor. RSS is a secondary detail.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24)
            ProcessList(groups: monitor.snapshot.groups, metric: model.metric, trends: model.trends, sampledAt: model.sampledAt)
        }.onExitCommand(perform: back)
    }
}
struct OwnerSparkline: View {
    let points: [PlotPoint]
    let now: Date
    let metric: ProcessMetric
    var body: some View {
        let ceiling = max(1, points.map(\.value).max() ?? 1)
        TraceShape(points: TraceGeometry.window(points, ending: now, seconds: 60, ceiling: ceiling))
            .stroke(metric == .memory ? Color.teal : .blue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(height: 28).padding(.horizontal, 16)
            .accessibilityLabel("\(metric.label) over the last 60 seconds, \(points.count) readings")
            .transaction { $0.animation = nil }
    }
}

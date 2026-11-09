import SwiftUI
import PulseCore

enum Vital: String, CaseIterable, Identifiable {
    case memory = "Memory", cpu = "CPU", heat = "Heat", disk = "Disk"
    var id: String { rawValue }
    var symbol: String { switch self { case .memory: "memorychip"; case .cpu: "cpu"; case .heat: "thermometer.medium"; case .disk: "internaldrive" } }
    func value(_ s: Snapshot) -> String {
        switch self {
        case .memory: MetricFormat.percent(s.memoryPercent)
        case .cpu: MetricFormat.percent(s.cpu)
        case .heat: s.effectiveTemperature.map { String(format: "%.0f°", $0) } ?? "—"
        case .disk: MetricFormat.bytes(s.diskFree)
        }
    }
    func points(_ plots: PlotHistory, _ s: Snapshot) -> [PlotPoint] { switch self { case .memory: plots.memory; case .cpu: plots.cpu; case .heat: s.effectiveTemperature == nil ? plots.thermal : plots.temperature; case .disk: plots.disk } }
    func domain(_ s: Snapshot) -> ClosedRange<Double> { switch self { case .cpu, .memory: 0...100; case .heat: s.effectiveTemperature == nil ? 0...3 : 0...150; case .disk: 0...max(1, Double(s.diskTotal ?? 1)) } }
    func lines(_ s: Snapshot) -> [String] {
        switch self {
        case .memory: ["\(s.pressure.rawValue) pressure", "Swap \(MetricFormat.bytes(s.swap)) · compressed \(MetricFormat.bytes(s.compressed))"]
        case .cpu: ["P \(MetricFormat.percent(s.performanceCPU)) · E \(MetricFormat.percent(s.efficiencyCPU))", "Across all cores"]
        case .heat: [s.heatLevel.rawValue, "macOS thermal: \(s.thermal.lowercased())", s.fans.isEmpty ? "Fan unavailable" : "Fan \(Int(s.fans.max() ?? 0)) rpm"]
        case .disk: ["\(MetricFormat.bytes(s.diskTotal)) capacity", "\(MetricFormat.bytes(s.bytesWritten)) written since boot"]
        }
    }
    func explanation(_ s: Snapshot) -> String {
        switch self {
        case .memory: "\(MetricFormat.bytes(s.memoryUsed)) used of \(MetricFormat.bytes(s.memoryTotal)). Compressed RAM: \(MetricFormat.bytes(s.compressed)). System free: \(MetricFormat.percent(s.memoryFreePercent)). Existing swap alone does not mean current pressure."
        case .cpu: "Total CPU use across all cores. Process CPU uses 100% per core. P means performance cores; E means efficiency cores. CPU warning requires more than 85% for 30 seconds of readings."
        case .heat: "\(s.sensorStatus). Cool below 70°C; Warm 70–85°C; Hot 85–95°C; Throttling risk at 95°C or serious/critical macOS thermal state. Risk is not proof of throttling."
        case .disk: "\(MetricFormat.bytes(s.writtenToday)) written since first reading today. \(s.baselineStatus). Boot writes sum all storage drivers, including virtual/removable devices. This is not SSD wear."
        }
    }
}
struct VitalGrid: View {
    let snapshot: Snapshot
    let plots: PlotHistory
    let disk: DiskUsageModel
    var compact = false
    var onSelect: ((Vital) -> Void)?
    var body: some View {
        Grid(horizontalSpacing: compact ? 8 : 12, verticalSpacing: compact ? 8 : 12) {
            GridRow(alignment: .top) { tile(.memory); tile(.cpu) }
            GridRow(alignment: .top) { tile(.heat); tile(.disk) }
        }
    }
    private func tile(_ vital: Vital) -> some View {
        VitalTile(vital: vital, snapshot: snapshot, plots: plots, disk: disk, compact: compact, onDrilldown: (vital == .memory || vital == .cpu) ? onSelect.map { select in { select(vital) } } : nil)
    }
}
struct VitalTile: View {
    let vital: Vital
    let snapshot: Snapshot
    let plots: PlotHistory
    let disk: DiskUsageModel
    var compact = false
    var onDrilldown: (() -> Void)?
    @State private var hovered = false
    @State private var showExplanation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var tint: Color {
        switch vital {
        case .heat: snapshot.heatTone.color
        case .memory: snapshot.memoryTone.color
        case .cpu: snapshot.cpuTone.color
        case .disk: snapshot.diskTone.color
        }
    }
    private var footerLines: [String] {
        if compact && vital == .heat { return ["\(snapshot.heatLevel.rawValue) · macOS \(snapshot.thermal.lowercased())", snapshot.fans.isEmpty ? "Fan unavailable" : "Fan \(Int(snapshot.fans.max() ?? 0)) rpm"] }
        if compact && vital == .memory { return ["\(snapshot.pressure.rawValue) pressure", "Swap \(MetricFormat.bytes(snapshot.swap)) · compressed \(MetricFormat.bytes(snapshot.compressed))"] }
        if compact && vital == .disk { return ["\(MetricFormat.bytes(snapshot.bytesWritten)) written since boot"] }
        return vital.lines(snapshot)
    }
    var body: some View {
        Button {
            if let onDrilldown { onDrilldown() }
            else { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { showExplanation.toggle() } }
        } label: {
            VStack(alignment: .leading, spacing: compact ? 5 : 10) {
                HStack {
                    Label(vital.rawValue, systemImage: vital.symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: onDrilldown != nil ? "arrow.right.circle" : showExplanation ? "minus.circle" : "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                if vital == .cpu || vital == .memory {
                    MeterRing(value: (vital == .cpu ? snapshot.cpu : snapshot.memoryPercent).map { $0.rounded() }, tint: tint, diameter: compact ? 62 : 86).equatable().frame(maxWidth: .infinity)
                } else {
                    Text(vital.value(snapshot) + (vital == .disk ? " free" : "")).font(.system(size: compact ? 25 : 30, weight: .semibold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                if vital == .heat { HeatBar(temperature: snapshot.effectiveTemperature) }
                if vital == .disk { DiskBreakdownView(snapshot: snapshot, disk: disk, compact: compact) }
                HistoryChart(points: vital.points(plots, snapshot), domain: vital.domain(snapshot), tint: tint).frame(height: compact ? 10 : 24)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(footerLines, id: \.self) {
                        Text($0).font(.system(size: compact ? 10 : 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.renderBounds("footer-" + vital.id, enabled: compact)
                if showExplanation { Text(vital.explanation(snapshot)).font(.caption).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, minHeight: compact ? 0 : 160, alignment: .topLeading).padding(compact ? 10 : 14).contentShape(.rect)
        }.buttonStyle(.plain).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(VitalPlateSurface(tint: tint))
            .background(tint.opacity(hovered && onDrilldown != nil ? 0.08 : 0), in: .rect(cornerRadius: 16))
            .onHover { hovered = $0 }
            .renderBounds((compact ? "tile-" : "overview-tile-") + vital.id, space: compact ? "glance-viewport" : "overview-viewport")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(onDrilldown != nil ? "Show processes by \(vital.rawValue)" : "\(vital.rawValue), \(vital.value(snapshot)), \(vital.lines(snapshot).joined(separator: ", "))" + (showExplanation ? ". " + vital.explanation(snapshot) : ""))
            .accessibilityValue(vital.value(snapshot))
            .accessibilityHint(onDrilldown != nil ? "Open grouped processes" : showExplanation ? "Collapse explanation" : "Explain this reading")
    }
}

import SwiftUI
import PulseCore

enum TimelineRange: String, CaseIterable, Identifiable {
    case hour = "1 hour", six = "6 hours", day = "24 hours"
    var id: String { rawValue }
    var seconds: Double { switch self { case .hour: 3600; case .six: 21_600; case .day: 86_400 } }
    /// Newest samples inside the range, reduced to a drawable size without losing the worst level of any merged group.
    func samples(_ all: [TimelineSample]) -> [TimelineSample] {
        guard let last = all.last?.time else { return [] }
        return TimelineSample.reduce(all.filter { $0.time >= last - seconds }, limit: 240)
    }
}
struct RangePicker: View {
    @Binding var range: TimelineRange
    var body: some View {
        Picker("Range", selection: $range) { ForEach(TimelineRange.allCases) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.segmented).frame(width: 260).labelsHidden()
    }
}
private func clock(_ time: Double?) -> String {
    time.map { Date(timeIntervalSince1970: $0).formatted(date: .omitted, time: .shortened) } ?? "Waiting"
}
/// A measured line with real axis labels; nothing is smoothed or invented.
struct TimelineLine: View {
    let title: String
    let points: [PlotPoint]
    let tint: Color
    let format: (Double) -> String
    var body: some View {
        let ceiling = max(1, (points.map(\.value).max() ?? 1) * 1.1)
        let coordinates = TraceGeometry.timeline(points, domain: 0...ceiling)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(points.last.map { format($0.value) } ?? "No readings").font(.subheadline.monospacedDigit()).foregroundStyle(tint)
            }
            ZStack(alignment: .bottomLeading) {
                TraceGrid().stroke(.primary.opacity(0.07), style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                TraceShape(points: coordinates, filled: true).fill(tint.opacity(points.count > 1 ? 0.14 : 0))
                TraceShape(points: coordinates).stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if points.count < 2 { Text("Collecting readings").font(.caption2).foregroundStyle(.secondary) }
            }.frame(height: 90)
            HStack {
                Text(clock(points.first?.date.timeIntervalSince1970))
                Spacer()
                Text("0 – " + format(ceiling))
                Spacer()
                Text("Now")
            }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }.transaction { $0.animation = nil }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) over time, latest \(points.last.map { format($0.value) } ?? "unavailable"), \(points.count) readings")
    }
}
/// A colored strip: one slice per measured bucket, colored by its worst level.
struct LevelBand: View {
    let title: String
    let samples: [TimelineSample]
    let level: (TimelineSample) -> UInt8
    let color: (UInt8) -> Color
    let legend: [(String, Color)]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            ZStack {
                ForEach(Array(Set(samples.map(level))).sorted(), id: \.self) { value in
                    BandShape(times: samples.map(\.time), active: samples.map { level($0) == value }).fill(color(value))
                }
            }.frame(height: 26).clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay { if samples.count < 2 { Text("Collecting readings").font(.caption2).foregroundStyle(.secondary) } }
            HStack(spacing: 14) {
                Text(clock(samples.first?.time))
                Spacer()
                ForEach(legend, id: \.0) { item in
                    HStack(spacing: 4) { Circle().fill(item.1).frame(width: 7, height: 7); Text(item.0) }
                }
                Spacer()
                Text("Now")
            }.font(.caption2).foregroundStyle(.secondary)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title); \(samples.count) readings; \(legend.map(\.0).joined(separator: ", "))")
    }
}
/// Filled slices of a strip for the buckets where `active` is true; plain paths, no GPU plotting pool.
private struct BandShape: Shape {
    let times: [Double]
    let active: [Bool]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = times.first, let last = times.last else { return path }
        let duration = max(1, last - first)
        for index in times.indices where active[index] {
            let start = (times[index] - first) / duration * rect.width
            let end = index + 1 < times.count ? (times[index + 1] - first) / duration * rect.width : rect.width
            path.addRect(CGRect(x: rect.minX + start, y: rect.minY, width: max(1.5, end - start), height: rect.height))
        }
        return path
    }
}
extension TimelineSample {
    var swapPoint: PlotPoint? { swap.map { PlotPoint(date: Date(timeIntervalSince1970: time), value: Double($0)) } }
}
func pressureColor(_ level: UInt8) -> Color { level == 1 ? .green : level == 2 ? .yellow : level >= 4 ? .red : .gray.opacity(0.4) }
func thermalColor(_ level: UInt8) -> Color {
    switch level { case 0: .green; case 1: .yellow; case 2: .orange; case 3: .red; default: .gray.opacity(0.4) }
}

import SwiftUI
import PulseCore

/// Quantized display input and a narrow animation boundary keep glass/text out of interpolation.
struct MeterRing: View, Equatable {
    let value: Double?
    var tint = Color.teal
    var diameter: CGFloat = 86
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value && lhs.tint == rhs.tint && lhs.diameter == rhs.diameter
    }
    var body: some View {
        let _ = RenderDiagnostics.shared.record("ring.body")
        ZStack {
            LayerRing(fraction: max(0, min(1, (value ?? 0) / 100)), tint: value == nil ? .clear : tint, animate: !reduceMotion)
                .frame(width: diameter + 6, height: diameter + 6)
            Text(value.map { String(format: "%.0f%%", $0) } ?? "—")
                .font(.system(size: diameter < 80 ? 21 : 25, weight: .semibold, design: .rounded)).monospacedDigit()
        }.frame(width: diameter, height: diameter).padding(3)
            .transaction { $0.animation = nil }
            .onChange(of: value) { RenderDiagnostics.shared.record("ring.target") }
            .accessibilityLabel("\(MetricFormat.percent(value)), range zero to 100 percent")
    }
}
struct HeatBar: View {
    let temperature: Double?
    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        Rectangle().fill(HeatLevel.cool.tone.color.opacity(0.5)).frame(width: geometry.size.width * 70 / 110)
                        Rectangle().fill(HeatLevel.warm.tone.color.opacity(0.6)).frame(width: geometry.size.width * 15 / 110)
                        Rectangle().fill(HeatLevel.hot.tone.color.opacity(0.6)).frame(width: geometry.size.width * 10 / 110)
                        Rectangle().fill(HeatLevel.risk.tone.color.opacity(0.8))
                    }.clipShape(Capsule())
                    if let temperature {
                        Circle().fill(.primary).frame(width: 9, height: 9)
                            .offset(x: max(0, min(geometry.size.width - 9, geometry.size.width * temperature / 110 - 4.5)))
                    }
                }
            }.frame(height: 8)
            HStack { Text("0°"); Spacer(); Text("70 / 85 / 95°C") }.font(.caption2).foregroundStyle(.secondary)
        }.accessibilityLabel(temperature.map { "\(Int($0)) degrees Celsius; warm 70, hot 85, risk 95" } ?? "Temperature unavailable")
    }
}

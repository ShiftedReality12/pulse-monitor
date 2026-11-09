import SwiftUI
import PulseCore

enum HealthStyle {
    static func tint(_ s: Snapshot) -> Color { s.healthTone.color }
    static func badge(_ s: Snapshot) -> String {
        switch s.signal {
        case .heat: "Hot"
        case .memory: "Memory pressure"
        case .disk: "Low disk"
        case .cpu: "Busy"
        case .unavailable: "Limited readings"
        case .none: s.heatLevel == .hot ? "Hot" : s.heatLevel == .warm ? "Busy" : "Calm"
        }
    }
}
extension Tone {
    var color: Color {
        switch self {
        case .calm: .teal
        case .warm: .orange
        case .hot: .pink
        case .risk: .red
        case .unavailable: .secondary
        }
    }
}
struct VitalPlateSurface: ViewModifier {
    var tint = Color.teal
    func body(content: Content) -> some View {
        // Chrome supplies the backdrop; tiles need only independent, static plates.
        content.background { VitalPlate(tint: tint).equatable() }
    }
}
private struct VitalPlate: View, Equatable {
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.tint == rhs.tint }
    var body: some View {
        let _ = RenderDiagnostics.shared.record("plate.background")
        let opaque = reduceTransparency || contrast == .increased
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(opaque ? 1 : 0.45))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(contrast == .increased ? Color.primary.opacity(0.5) : tint.opacity(0.18)))
    }
}
struct ContentCard: ViewModifier {
    var inset: CGFloat = 20
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.padding(inset)
            .background(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .controlBackgroundColor).opacity(0.55), in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(contrast == .increased ? 0.5 : 0.08)))
    }
}

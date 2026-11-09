import SwiftUI
import PulseCore

struct VerdictHero: View {
    let copy: HumanCopy
    var compact = false
    private var tint: Color { copy.tone.color }
    var body: some View {
        HStack(alignment: .top, spacing: compact ? 12 : 20) {
            Image(systemName: copy.symbol).symbolRenderingMode(.hierarchical)
                .font(.system(size: compact ? 32 : 54, weight: .medium)).foregroundStyle(tint)
                .frame(width: compact ? 38 : 64)
            VStack(alignment: .leading, spacing: compact ? 5 : 9) {
                if !compact { Text("PULSE").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(tint) }
                Text(copy.headline).font(compact ? .headline : .system(.title2, design: .rounded, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(copy.ownerLine).font(compact ? .caption : .callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(compact ? 12 : 22).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(tint.opacity(0.09)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(tint.opacity(0.14)))
            .accessibilityElement(children: .combine)
    }
}
struct OwnerRow: View, Equatable {
    let group: ProcessGroup
    var compact = false
    var metric: ProcessMetric?
    private var metricText: String { metric == .memory ? group.memoryLabel : group.cpuSummary ?? "CPU unavailable" }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.group == rhs.group && lhs.compact == rhs.compact && lhs.metric == rhs.metric }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: group.category == "AI session" ? "sparkles" : group.category == "App" ? "app.dashed" : "terminal")
                .font(.title3).frame(width: 26, height: 30).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: compact ? 2 : 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(HumanCopy.ownerName(group)).font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(metric != nil ? metricText : compact ? group.compactMetrics : String(format: "%.1f", group.impact)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text("What: " + group.explanation).font(.system(size: compact ? 10 : 12)).foregroundStyle(.secondary).lineLimit(compact ? 1 : 2)
                Text("Why: " + group.runningReason).font(.system(size: compact ? 10 : 12)).foregroundStyle(.secondary).lineLimit(compact ? 1 : 2)
                if !compact { Text(group.why).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(2) }
            }
        }.accessibilityElement(children: .combine).help("\(group.why) · impact \(String(format: "%.1f", group.impact))\n\(group.explanation)\nWhy is this running? \(group.runningReason)\nFolder: \(group.cwd ?? "Unavailable")")
    }
}
struct OwnerDisclosure: View {
    let group: ProcessGroup
    var metric: ProcessMetric?
    @State private var expanded = false
    @Namespace private var row
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text("What it is").font(.caption.weight(.semibold))
                Text(group.explanation)
                Text("Why is this running?").font(.caption.weight(.semibold))
                Text(group.runningReason)
                Text(group.cwd ?? "Working folder unavailable").textSelection(.enabled)
                Text("PIDs: " + group.members.map(String.init).joined(separator: ", ")).font(.caption.monospaced())
                if group.limited { Text("Some identity or resource reads are limited by macOS.").foregroundStyle(.secondary) }
            }.font(.callout).padding(.top, 10).textSelection(.enabled)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(group.category).font(.caption2.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 3).background(.quaternary, in: .capsule)
                    .matchedGeometryEffect(id: group.id, in: row)
                OwnerRow(group: group, metric: metric).equatable()
            }
        }.padding(16).background(.primary.opacity(0.025), in: .rect(cornerRadius: 16))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: expanded)
    }
}

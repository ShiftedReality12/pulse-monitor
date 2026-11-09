import SwiftUI
import PulseCore

/// Every running AI agent CLI session with its account, pane, folder, uptime and combined memory/CPU (F1).
struct SessionsSection: View {
    let snapshot: Snapshot
    var showAccounts = true
    var showPanes = true
    private var sessions: [ProcessGroup] { snapshot.groups.filter { $0.category == "AI session" } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("Your AI workspace").font(.largeTitle.weight(.semibold))
                Text(summary).foregroundStyle(.secondary)
                if sessions.isEmpty { ContentUnavailableView("No readable AI sessions", systemImage: "terminal", description: Text("Open an AI coding session (Claude Code or Codex) to see its folder and resource use here.")) }
                ForEach(sessions) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Label(HumanCopy.ownerName(group), systemImage: "sparkles").font(.headline).lineLimit(1)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(group.memoryLabel).font(.title3.weight(.semibold).monospacedDigit())
                                Text(group.cpuSummary ?? "CPU unavailable").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                if showAccounts, let home = group.configHome { Label("Account folder: " + home, systemImage: "person.crop.circle").textSelection(.enabled) }
                                if showPanes, let pane = group.pane { Label("pane " + pane, systemImage: "rectangle.split.2x1") }
                                Label(group.cwd ?? "Working folder unavailable", systemImage: "folder").textSelection(.enabled)
                                Label(uptime(group) + " · started by " + (group.launcher ?? "an unavailable launcher"), systemImage: "clock")
                                Text("\(group.members.count) processes (including child tools) · PIDs " + group.members.prefix(6).map(String.init).joined(separator: ", ") + (group.members.count > 6 ? "…" : ""))
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }.font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            MemorySparkline(values: group.memoryTrend).frame(width: 140, height: 40)
                        }
                        Text("What: " + group.explanation).font(.caption).foregroundStyle(.secondary)
                    }.modifier(ContentCard())
                }
                Text(HumanCopy.partialFootnote).font(.caption2).foregroundStyle(.secondary)
                Text("Memory and CPU are summed over the session and its child tools; CPU is per core. Account and pane are read from the session's own start-up settings. Missing launch identities are never inferred.").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
    private var summary: String {
        let memory = sessions.compactMap(\.resident).reduce(0, +), cpu = sessions.compactMap(\.cpu).reduce(0, +)
        return "\(sessions.count) sessions · \(snapshot.aiProcessCount) AI processes · \(MetricFormat.bytes(memory)) memory · " + String(format: "%.1f%% CPU", cpu) + " combined"
    }
    private func uptime(_ group: ProcessGroup) -> String {
        guard let start = group.startedAt else { return "Uptime unavailable" }
        let minutes = max(0, Int(snapshot.date.timeIntervalSince(start) / 60))
        return minutes >= 1440 ? "Running \(minutes / 1440)d \(minutes % 1440 / 60)h" : "Running \(minutes / 60)h \(minutes % 60)m"
    }
}
private struct MemorySparkline: View {
    let values: [Double]
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TraceShape(points: TraceGeometry.readings(values))
                .stroke(.teal, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            Text("RAM · \(values.count) readings").font(.caption2).foregroundStyle(.secondary)
        }.accessibilityLabel("RAM trend, \(values.count) readings")
    }
}

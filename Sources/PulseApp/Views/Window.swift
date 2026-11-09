import SwiftUI
import PulseCore

enum WindowSection: String, CaseIterable, Identifiable {
    case overview = "Overview", processes = "Processes", sessions = "Sessions", leaks = "Leak watch", memory = "Memory", disk = "Disk", heat = "Heat"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"; case .processes: "list.bullet.rectangle"; case .sessions: "terminal"; case .leaks: "drop.degreesign"
        case .memory: "memorychip"; case .disk: "internaldrive"; case .heat: "thermometer.medium"
        }
    }
    var names: [String] { self == .leaks ? ["leak", "leaks"] : [rawValue.lowercased()] }
    /// `--show-section memory|leaks|sessions|disk|heat|processes|overview` opens a section directly.
    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "--show-section"), arguments.indices.contains(index + 1),
              let match = Self.allCases.first(where: { $0.names.contains(arguments[index + 1].lowercased()) }) else { return nil }
        self = match
    }
}
struct PulseWindow: View {
    @Bindable var monitor: Monitor
    @State private var destination = DetailDestination(arguments: CommandLine.arguments)
    @State private var section: WindowSection? = WindowSection(arguments: CommandLine.arguments) ?? .overview
    var body: some View {
        NavigationSplitView {
            List(WindowSection.allCases, selection: $section) { item in Label(item.rawValue, systemImage: item.symbol).tag(item) }
                .scrollContentBackground(.hidden)
                .navigationSplitViewColumnWidth(180)
        } detail: {
            if let destination {
                switch destination {
                case .processes: ProcessDrilldown(monitor: monitor, back: closeDetail)
                }
            } else { WindowDetail(monitor: monitor, section: section ?? .overview, showProcesses: showProcesses) }
        }.toolbar(removing: .sidebarToggle)
            .toolbarVisibility(.hidden, for: .windowToolbar)
            .frame(minWidth: 850, minHeight: 650)
            .containerBackground(.clear, for: .window)
            .onAppear {
                monitor.visibility("window", shown: true)
                if case let .processes(metric) = destination { showProcesses(metric) }
            }
            .onChange(of: section) { closeDetail() }
            .task { await followSectionFile() }
            .onDisappear { closeDetail(); monitor.visibility("window", shown: false) }
    }
    private func showProcesses(_ metric: ProcessMetric) {
        destination = .processes(metric); monitor.drilldown.open(metric)
        monitor.drilldown.record(groups: monitor.snapshot.groups, sampledAt: monitor.snapshot.processSampleDate)
    }
    /// Evidence hook: when PULSE_SECTION_FILE names a file, its text selects the section (same names as `--show-section`).
    private func followSectionFile() async {
        guard let path = ProcessInfo.processInfo.environment["PULSE_SECTION_FILE"] else { return }
        while !Task.isCancelled {
            if let text = try? String(contentsOfFile: path, encoding: .utf8),
               let match = WindowSection(arguments: ["--show-section", text.trimmingCharacters(in: .whitespacesAndNewlines)]), match != section { section = match }
            try? await Task.sleep(for: .seconds(1))
        }
    }
    private func closeDetail() { destination = nil; monitor.drilldown.close() }
}
/// Only the selected detail reads changing measurements; sidebar and unselected sections stay idle.
private struct WindowDetail: View {
    let monitor: Monitor
    let section: WindowSection
    let showProcesses: (ProcessMetric) -> Void
    var body: some View {
        let _ = monitor.renderToken
        let _ = RenderDiagnostics.shared.record("section." + section.rawValue)
        Group {
            switch section {
            case .overview:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        VerdictHero(copy: monitor.verdict)
                        UsageStrip(model: monitor.usage)
                        if let leak = monitor.insights.leaks.first {
                            Label("Leak watch: " + leak.title + " is climbing about " + MetricFormat.bytes(UInt64(max(0, leak.slopePerHour))) + "/hour. Open Leak watch for details.", systemImage: "exclamationmark.triangle")
                                .font(.callout).foregroundStyle(.orange)
                        }
                        VitalGrid(snapshot: monitor.snapshot, plots: monitor.plots, disk: monitor.disk, onSelect: { showProcesses($0 == .memory ? .memory : .cpu) })
                        Text("The last hour, at a glance").font(.title2.weight(.semibold))
                        HStack {
                            timeline("CPU", points: monitor.plots.cpu, tone: monitor.snapshot.cpuTone)
                            timeline("Memory", points: monitor.plots.memory, tone: monitor.snapshot.memoryTone)
                        }
                        Text("Biggest users").font(.headline)
                        ForEach(Array(monitor.snapshot.groups.prefix(3))) { OwnerRow(group: $0).equatable() }
                        Text(HumanCopy.partialFootnote).font(.caption2).foregroundStyle(.secondary)
                    }.padding(28)
                }.coordinateSpace(name: "overview-viewport")
                    .onPreferenceChange(GlanceBoundsKey.self) { RenderDiagnostics.shared.captureBounds($0) }
            case .processes: ProcessList(groups: monitor.snapshot.groups)
            case .disk: DiskSection(snapshot: monitor.snapshot, plots: monitor.plots, disk: monitor.disk, insights: monitor.insights)
            case .sessions: SessionsSection(snapshot: monitor.snapshot, showAccounts: monitor.hasProvider("agent-accounts"), showPanes: monitor.hasProvider("herdr"))
            case .leaks: LeakSection(insights: monitor.insights)
            case .memory: MemorySection(monitor: monitor)
            case .heat: HeatSection(snapshot: monitor.snapshot, plots: monitor.plots, insights: monitor.insights)
            }
        }.navigationTitle(section.rawValue)
    }
    private func timeline(_ title: String, points: [PlotPoint], tone: Tone) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(tone.color)
            HistoryChart(points: points, domain: 0...100, tint: tone.color, axes: true).frame(height: 130)
        }.padding(14).frame(maxWidth: .infinity).modifier(VitalPlateSurface(tint: tone.color))
    }
}

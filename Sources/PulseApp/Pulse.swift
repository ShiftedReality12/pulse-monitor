import SwiftUI
import PulseCore

@main
struct PulseLauncher {
    static func main() {
        DiskIOPolicy.disableMaterialization()
        if CommandLine.arguments.contains("--disk-bench") {
            DiskBenchmark.run()
        } else if let index = CommandLine.arguments.firstIndex(where: { $0 == "--render-bench" || $0 == "--present-bench" }) {
            guard CommandLine.arguments.indices.contains(index + 1), let seconds = Double(CommandLine.arguments[index + 1]), seconds.isFinite, seconds > 0 else { fputs("Usage: Pulse --render-bench <positive seconds>\n", stderr); exit(2) }
            RenderBenchmark.run(seconds: seconds, presented: CommandLine.arguments[index] == "--present-bench")
        } else if let index = CommandLine.arguments.firstIndex(of: "--bench") {
            guard CommandLine.arguments.indices.contains(index + 1), let seconds = Double(CommandLine.arguments[index + 1]), seconds.isFinite, seconds > 0 else { fputs("Usage: Pulse --bench <positive seconds> [--visible]\n", stderr); exit(2) }
            Benchmark.run(seconds: seconds, visible: CommandLine.arguments.contains("--visible"))
        } else if CommandLine.arguments.contains("--dump-json") {
            let sampler = Sampler(); _ = sampler.sample(forceProcessRefresh: true)
            Thread.sleep(forTimeInterval: 2)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            do { print(String(decoding: try encoder.encode(sampler.sample(forceProcessRefresh: true)), as: UTF8.self)) }
            catch { fputs("Could not encode metrics: \(error)\n", stderr); exit(1) }
        } else { PulseApp.main() }
    }
}
struct PulseApp: App {
    @State private var monitor = Monitor.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra {
            GlanceView(monitor: monitor, openOverview: delegate.showOverview)
        } label: {
            Label(monitor.menuText, systemImage: monitor.menuWarning ? "exclamationmark.circle" : "gauge.with.dots.needle.33percent")
                .accessibilityLabel("Pulse. \(monitor.menuVerdict)")
        }.menuBarExtraStyle(.window)
        Settings {
            Form {
                LabeledContent("Refresh", value: "2 seconds open · 5 seconds closed")
                LabeledContent("Processes", value: "6 seconds open · every 30 seconds when closed")
                LabeledContent("History", value: "Last hour · at most 120 plotted points")
                Text("Readings are local. Missing permissions stay visible.")
            }.padding(24).frame(width: 420)
        }
    }
}

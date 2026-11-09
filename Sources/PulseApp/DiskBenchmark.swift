import Foundation
import PulseCore

enum DiskBenchmark {
    static func advancedEntries(previous: [String: Int], current: [String: Int]) -> Int {
        current.reduce(0) { sum, item in
            let old = previous[item.key] ?? 0
            return sum + (item.value >= old ? item.value - old : item.value)
        }
    }
    static func run() {
        let arguments = CommandLine.arguments
        let untilComplete = arguments.contains("--until-complete")
        var roots: [URL]?
        if let index = arguments.firstIndex(of: "--root") {
            guard arguments.indices.contains(index + 1) else { fputs("--root requires a path\n", stderr); exit(2) }
            roots = [URL(fileURLWithPath: NSString(string: arguments[index + 1]).expandingTildeInPath)]
        }
        let cacheIndex = arguments.firstIndex(of: "--cache")
        let cache = cacheIndex.flatMap { arguments.indices.contains($0 + 1) ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
        let selected = roots, done = DispatchSemaphore(value: 0)
        Task.detached(priority: .utility) {
            let service = DiskEstimates(cacheURL: cache)
            let cachedStart = ProcessInfo.processInfo.systemUptime
            let cached = await service.cachedEstimates()
            let cachedCounters = await service.scanEntries()
            var previousCounters = cachedCounters, visitedEntries = 0
            let cachedSeconds = ProcessInfo.processInfo.systemUptime - cachedStart
            let start = ProcessInfo.processInfo.systemUptime, initial = Benchmark.usage()
            let duration = untilComplete ? 300.0 : 60.0
            var passes: [[String: Any]] = [], complete = false
            var duty = DiskScanDuty()
            duty.reset(wall: start, cpu: Benchmark.cpu(initial))
            let windowCadence = arguments.contains("--window-cadence")
            repeat {
                let passStart = ProcessInfo.processInfo.systemUptime, passCPU = Benchmark.cpu(Benchmark.usage())
                let allowance = windowCadence ? duty.allowance(wall: passStart, cpu: Benchmark.cpu(Benchmark.usage()), fullWindow: true) : 3
                if windowCadence && allowance < 0.0005 {
                    if passStart - start >= duration { break }
                    try? await Task.sleep(for: .milliseconds(200)); continue
                }
                let results = await service.load(roots: selected, seconds: min(3, max(0, duration - (passStart - start))), cpuSeconds: windowCadence ? allowance : nil)
                let descriptors = await service.openDirectoryCount()
                let entries = await service.scanEntries()
                visitedEntries += advancedEntries(previous: previousCounters, current: entries); previousCounters = entries
                let pending = await service.hasPendingWork()
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                complete = !pending && !results.isEmpty && results.filter { $0.path != "pulse:node_modules" }.allSatisfy(\.complete)
                passes.append(["pass": passes.count + 1, "elapsed_seconds": elapsed,
                               "pass_seconds": ProcessInfo.processInfo.systemUptime - passStart,
                               "cpu_seconds": Benchmark.cpu(Benchmark.usage()) - passCPU,
                               "entries": entries.values.reduce(0, +), "open_directory_descriptors": descriptors,
                               "roots": results.map { result -> [String: Any] in
                    ["path": EvidencePath.display(result.path), "complete": result.complete,
                     "bytes": result.bytes as Any? ?? NSNull(), "entries": entries[result.path] ?? 0, "seconds": elapsed]
                }])
                if elapsed >= duration || (untilComplete && complete) { break }
                if untilComplete && !complete && !pending { break }
                if windowCadence { try? await Task.sleep(for: .milliseconds(200)) }
                else if !untilComplete { try? await Task.sleep(for: .seconds(min(2, duration - elapsed))) }
            } while true
            let wall = ProcessInfo.processInfo.systemUptime - start, cpu = Benchmark.cpu(Benchmark.usage()) - Benchmark.cpu(initial)
            let totalEntries = await service.scanEntries().values.reduce(0, +)
            let entries = visitedEntries
            let settleStart = ProcessInfo.processInfo.systemUptime
            if cache != nil && complete {
                try? await Task.sleep(for: .seconds(31)) // Let the real throttled checkpoint persist completion.
            }
            var steady: [[String: Any]] = []
            let steadyStart = Benchmark.cpu(Benchmark.usage()), steadyWall = ProcessInfo.processInfo.systemUptime
            if arguments.contains("--steady") {
                for _ in 0..<30 {
                    let results = await service.load(roots: selected)
                    steady.append(["seconds": ProcessInfo.processInfo.systemUptime - steadyWall,
                                   "complete": results.allSatisfy(\.complete), "footprint_mb": Double(Benchmark.footprint() ?? 0) / 1e6])
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            let steadyCPU = Benchmark.cpu(Benchmark.usage()) - steadyStart
            let output: [String: Any] = ["scope": "local execution, real scanner; no presented budget proof",
                "cached_seconds": cachedSeconds, "cached_complete": !cached.isEmpty && cached.allSatisfy(\.complete),
                "checkpoint_wait_seconds": ProcessInfo.processInfo.systemUptime - settleStart - (ProcessInfo.processInfo.systemUptime - steadyWall),
                "steady_samples": steady, "steady_cpu_percent": 100 * steadyCPU / max(0.001, ProcessInfo.processInfo.systemUptime - steadyWall),
                "window_cadence": windowCadence, "until_complete": untilComplete, "complete": complete, "wall_seconds": wall, "cpu_seconds": cpu,
                "entries": entries, "total_entries": totalEntries, "cpu_seconds_per_10k": 10_000 * cpu / Double(max(1, entries)), "wall_seconds_per_10k": 10_000 * wall / Double(max(1, entries)), "entries_per_cpu_second": Double(entries) / max(cpu, 0.000001),
                "cpu_percent": 100 * cpu / wall, "passes": passes]
            do {
                let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
                print(String(decoding: data, as: UTF8.self))
            } catch { fputs(EvidencePath.display("Disk benchmark encoding failed: \(error)\n"), stderr) }
            done.signal()
        }
        done.wait()
    }
}

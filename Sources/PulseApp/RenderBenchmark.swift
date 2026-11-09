import AppKit
import Darwin
import SwiftUI
import PulseCore

/// The same NSWindows/hosts as the app; never ordered onscreen in offscreen mode.
@MainActor enum RenderBenchmark {
    static func run(seconds: Double, presented: Bool = false) {
        fputs("Render self-check: native NSWindows; 10s warm-up, measured interval, settled idle audit.\n", stderr)
        NSApplication.shared.setActivationPolicy(presented ? .accessory : .prohibited)
        if presented { NSApplication.shared.finishLaunching() }
        let monitor = Monitor()
        let legacy = CommandLine.arguments.contains("--legacy-sizing")
        let overview = WindowHosts.overview(monitor: monitor, legacySizing: legacy)
        let glance = WindowHosts.glance(monitor: monitor, openOverview: { overview.window.makeKeyAndOrderFront(nil) }, legacySizing: legacy)
        let surfaces = [glance, overview]
        for (index, surface) in surfaces.enumerated() {
            if presented { surface.window.center(); surface.window.orderFront(nil) }
            else { surface.window.setFrameOrigin(NSPoint(x: -20_000 - index * 1500, y: -20_000)) }
        }
        if presented, let screen = NSScreen.main?.visibleFrame {
            overview.window.setFrameTopLeftPoint(NSPoint(x: screen.minX + 8, y: screen.maxY - 8))
            glance.window.setFrameTopLeftPoint(NSPoint(x: min(overview.window.frame.maxX + 8, screen.maxX - glance.window.frame.width), y: screen.maxY - 8))
            overview.window.makeKeyAndOrderFront(nil); glance.window.orderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        defer { for surface in surfaces { surface.window.contentView = nil; surface.window.close() } }
        monitor.visibility("render-bench", shown: true)
        defer { monitor.stopSampling() }
        let warmup = 10.0
        let started = ProcessInfo.processInfo.systemUptime
        var nextRender = started, initial: rusage?, measurementStart = started
        var measurementCounts: [String: Int] = [:]
        var memory: MemoryTelemetry?
        var renderPairs = 0, frames: [[String: Double]] = []
        while true {
            let now = ProcessInfo.processInfo.systemUptime
            if initial == nil && now - started >= warmup {
                initial = Benchmark.usage(); measurementStart = now
                measurementCounts = RenderDiagnostics.shared.snapshot()
                memory = MemoryTelemetry(start: now)
            }
            memory?.observe(at: now, force: initial != nil && now - measurementStart >= seconds)
            if presented && initial != nil && !BenchmarkCohort.valid(surfaces) {
                emit(["status": "INSUFFICIENT_EVIDENCE", "reason": "Both presented windows must be visible on a real screen", "cohort": BenchmarkCohort.report(surfaces), "surface_inventory": SurfaceInventory.capture(surfaces)])
                return
            }
            if let initial, now - measurementStart >= seconds {
                monitor.stopSampling()
                let final = Benchmark.usage(), wall = now - measurementStart
                let measuredFootprint = Benchmark.footprint()
                let measuredCounts = RenderDiagnostics.shared.snapshot().reduce(into: [String: Int]()) { result, entry in result[entry.key] = entry.value - (measurementCounts[entry.key] ?? 0) }
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
                let before = RenderDiagnostics.shared.snapshot(), idleStart = Benchmark.cpu(Benchmark.usage())
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 2))
                let after = RenderDiagnostics.shared.snapshot()
                let idle = after.reduce(into: [String: Int]()) { result, entry in result[entry.key] = entry.value - (before[entry.key] ?? 0) }
                let cpu = Benchmark.cpu(final) - Benchmark.cpu(initial)
                let bounds = RenderDiagnostics.shared.boundsSnapshot()
                let viewport = bounds["viewport"]
                let regionsFit = ["culprits", "footer-Heat"].allSatisfy { key in
                    guard let region = bounds[key], let viewport else { return false }
                    return (region["y"] ?? -1) >= 0 && (region["max_y"] ?? .infinity) <= (viewport["height"] ?? 0)
                }
                var result: [String: Any] = ["status": "MEASURED", "scope": presented ? "presented real NSWindows; native layout and compositor" : "real offscreen NSWindows with native layout and bitmap captures; not presented compositor budget proof", "presented": presented, "legacy_sizing": legacy, "measurement_render_count_deltas": measuredCounts, "warmup_seconds": warmup, "requested_seconds": seconds, "wall_seconds": wall, "cpu_seconds": cpu, "average_cpu_percent": 100 * cpu / wall, "max_rss_mb": Double(final.ru_maxrss) / 1e6, "render_pairs": renderPairs, "sampling_interval_seconds": 2, "frames": frames, "render_counts": after, "idle_after_settle_seconds": 2, "idle_cpu_seconds": Benchmark.cpu(Benchmark.usage()) - idleStart, "idle_render_count_deltas": idle, "glance_bounds": bounds, "glance_fitting_height": glance.initialSize.height, "glance_host_height": glance.host.frame.height, "glance_five_owner_count": min(5, monitor.snapshot.groups.count), "all_culprits_and_heat_footer_within_viewport": regionsFit && glance.initialSize.height <= glance.host.frame.height]
                result["tile_rows_equal_and_top_aligned"] = ["", "overview-"].allSatisfy { prefix in
                    [("Memory", "CPU"), ("Heat", "Disk")].allSatisfy { left, right in
                        guard let a = bounds[prefix + "tile-" + left], let b = bounds[prefix + "tile-" + right] else { return false }
                        return abs((a["y"] ?? -1) - (b["y"] ?? -2)) < 0.5 && abs((a["height"] ?? -1) - (b["height"] ?? -2)) < 0.5
                    }
                }
                result["footprint_series"] = memory?.report ?? [:]
                result["cohort"] = BenchmarkCohort.report(surfaces)
                result["large_layers"] = BenchmarkCohort.layers(surfaces)
                result["surface_inventory"] = SurfaceInventory.capture(surfaces)
                result["disk_capacity_consumed_by_view"] = RenderDiagnostics.shared.diskLoadSnapshot()
                result["disk_buckets_consumed_by_view"] = RenderDiagnostics.shared.diskSnapshot()
                if let measuredFootprint { result["phys_footprint_mb"] = Double(measuredFootprint) / 1e6 }
                emit(result); return
            }
            if now >= nextRender {
                autoreleasepool {
                    for surface in surfaces {
                        RenderDiagnostics.shared.record("window.layout.request")
                        if !presented {
                            surface.window.layoutIfNeeded()
                            let host = surface.host
                            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                                emit(["status": "INSUFFICIENT_EVIDENCE", "reason": "Native offscreen window capture unavailable"]); exit(77)
                            }
                            host.cacheDisplay(in: host.bounds, to: bitmap)
                        }
                    }
                }
                nextRender = now + SamplingPolicy.interval(visible: true)
                if let initial {
                    renderPairs += 1
                    frames.append(["elapsed": now - measurementStart, "cpu_seconds": Benchmark.cpu(Benchmark.usage()) - Benchmark.cpu(initial)])
                }
            }
            if memory?.excessive == true || monitor.snapshot.pressure == .critical || Benchmark.usage().ru_maxrss > 4_000_000_000 {
                fputs("Memory guard: red pressure or self exceeds 4 GB\n", stderr); exit(75)
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }
    private static func emit(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted]) else { return }
        print(String(decoding: data, as: UTF8.self))
    }
}

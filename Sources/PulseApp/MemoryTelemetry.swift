import Foundation
import PulseCore

/// 50ms observations plus two-second reporting buckets avoid aliasing a per-tick spike.
struct MemoryTelemetry {
    private var series: FootprintSeries
    private var nextPoll: Double
    private var lifetimePeak: UInt64?
    private var atMaximum: [String: Any] = [:]
    init(start: Double) { series = FootprintSeries(start: start); nextPoll = start }
    mutating func observe(at now: Double, force: Bool = false) {
        guard force || now >= nextPoll else { return }
        let memory = Benchmark.memory()
        if let memory, memory.current > (series.maximum ?? 0) {
            atMaximum = ["uptime": now, "phys_footprint_mb": Double(memory.current) / 1e6,
                         "graphics_scope": "Mach graphics tag ledger, charged + compressed; not individual texture owners"]
            if let graphics = memory.graphics { atMaximum["graphics_footprint_mb"] = Double(graphics) / 1e6 }
            if let uncharged = memory.graphicsUncharged { atMaximum["graphics_nofootprint_mb"] = Double(uncharged) / 1e6 }
            atMaximum["graphics_available"] = memory.graphics != nil
        }
        series.observe(at: now, bytes: memory?.current)
        if let peak = memory?.peak { lifetimePeak = max(lifetimePeak ?? peak, peak) }
        nextPoll = now + 0.05
    }
    var excessive: Bool { (series.maximum ?? 0) > 4_000_000_000 }
    var report: [String: Any] {
        var result: [String: Any] = [
            "observation_interval_seconds": 0.05, "report_interval_seconds": 2,
            "observations": series.observations, "missing_observations": series.missing,
            "skipped_intervals": series.skippedIntervals, "point_count": series.points.count,
            "points": series.points.map { ["elapsed": $0.elapsed, "footprint_mb": Double($0.bytes) / 1e6, "interval_peak_mb": Double($0.intervalPeak) / 1e6] }
        ]
        if let minimum = series.minimum { result["minimum_mb"] = Double(minimum) / 1e6 }
        if let maximum = series.maximum { result["maximum_mb"] = Double(maximum) / 1e6 }
        if let percentile95 = series.percentile95 { result["p95_mb"] = Double(percentile95) / 1e6 }
        result["p95_scope"] = "nearest-rank percentile of two-second interval peaks"
        result["at_maximum"] = atMaximum
        if let lifetimePeak { result["kernel_lifetime_peak_mb"] = Double(lifetimePeak) / 1e6 }
        return result
    }
}

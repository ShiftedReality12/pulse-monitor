import Foundation
import PulseCore

/// Opt-in counts, including interpolation paths; no timer or retained per-frame history.
final class RenderDiagnostics: @unchecked Sendable {
    static let shared = RenderDiagnostics()
    let enabled = CommandLine.arguments.contains("--render-bench") || CommandLine.arguments.contains("--present-bench") || CommandLine.arguments.contains("--render-diagnostics")
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    func record(_ event: String) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        counts[event, default: 0] += 1
    }
    private var bounds: [String: CGRect] = [:]
    private var diskLoadSeconds: Double?
    private var composition: [String: Any] = [:]
    func captureDiskLoad(seconds: Double) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }; diskLoadSeconds = seconds
    }
    func captureComposition(_ value: DiskComposition) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        composition = ["summary": value.summary, "total": value.total, "segments": value.segments.map { ["label": $0.label, "bytes": $0.bytes] }]
    }
    func diskLoadSnapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        var result = composition
        if let diskLoadSeconds { result["load_seconds"] = diskLoadSeconds }
        return result
    }
    private var diskBuckets: [[String: Any]] = []
    func captureDisk(_ buckets: [DiskBucket]) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        diskBuckets = buckets.map { ["path": EvidencePath.display($0.path), "label": $0.label, "bytes": $0.bytes, "partial": $0.partial, "is_project": $0.isProject] }
    }
    func diskSnapshot() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return diskBuckets
    }
    func captureBounds(_ value: [String: CGRect]) {
        lock.lock(); defer { lock.unlock() }
        bounds.merge(value, uniquingKeysWith: { _, new in new })
    }
    func boundsSnapshot() -> [String: [String: Double]] {
        lock.lock(); defer { lock.unlock() }
        return bounds.mapValues { ["x": $0.minX, "y": $0.minY, "width": $0.width, "height": $0.height, "max_y": $0.maxY] }
    }
    func publishIfRequested() {
        guard CommandLine.arguments.contains("--render-diagnostics") else { return }
        let value: [String: Any] = ["uptime": ProcessInfo.processInfo.systemUptime, "counts": snapshot(), "glance_bounds": boundsSnapshot()]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }
    }
    func snapshot() -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return counts
    }
}

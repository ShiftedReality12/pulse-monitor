import Foundation

public struct ProcessSample: Sendable {
    public var pid: Int32
    public var identity: UInt64
    public var name: String
    public var path: String
    public var resident: UInt64?
    public var cpu: Double?
    public var parent: Int32 = 0
    public var cwd: String?
    public var writesPerSecond: Double?
    /// Whitelisted agent context read from the process environment (never other variables).
    public var configDir: String?
    public var pane: String?
    /// True only when the process environment was actually readable; a failed read must not look like "no setting".
    public var agentEnvironmentRead = false
    /// RSS kept beside physical footprint. `resident` is the primary figure (footprint when the kernel provides it).
    public var rss: UInt64?
    public var uid: Int32 = -1
    /// Owning app pid for a launchd or XPC helper. 0 when the parent chain is enough.
    public var responsible: Int32 = 0
    public init(pid: Int32, identity: UInt64 = 0, name: String, path: String = "", resident: UInt64?, cpu: Double?) {
        self.pid = pid; self.identity = identity; self.name = name; self.path = path; self.resident = resident; self.cpu = cpu
    }
}
public struct ProcessGroup: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var members: [Int32]
    public var resident: UInt64?
    public var cpu: Double?
    public var limited: Bool
    public var category = "Background"
    public var explanation = ""
    public var runningReason = "Launch reason unavailable."
    public var startedAt: Date?
    public var launcher: String?
    public var cwd: String?
    public var aiProcessCount = 0
    public var writesPerSecond: Double?
    public var impact: Double = 0
    public var memoryTrend: [Double] = []
    public var hasVerifiedIdentity = false
    public var configHome: String?
    public var pane: String?
    /// True when every memory reading is missing because the process belongs to another user (root, DriverKit).
    public var needsAdmin = false
    public var rss: UInt64?
    public var cpuSummary: String? {
        guard let cpu, cpu.isFinite, cpu >= 0, !(limited && cpu < 0.5) else { return nil }
        if cpu > 0 && cpu < 0.1 { return "<0.1% CPU" }
        return String(format: "%.1f%%", cpu) + (limited ? "+" : "") + " CPU"
    }
    public var memoryLabel: String {
        if resident == nil && needsAdmin { return "needs admin" }
        return resident.map { MetricFormat.bytes($0) + (limited ? "+" : "") } ?? "RAM unavailable"
    }
    private var memorySummary: String { memoryLabel }
    public var compactMetrics: String { [cpuSummary, memorySummary].compactMap { $0 }.joined(separator: " · ") }
    public var why: String {
        let rate = writesPerSecond.map { MetricFormat.bytes(UInt64(max(0, $0))) + "/s writes" } ?? "writes unavailable"
        let rssNote: String? = rss.flatMap { value in resident.flatMap { primary in value == primary ? nil : "RSS " + MetricFormat.bytes(value) } }
        return [cpuSummary ?? (cpu == nil ? "CPU unavailable" : nil), memorySummary, rssNote, "\(members.count) processes", rate].compactMap { $0 }.joined(separator: " · ")
    }
}

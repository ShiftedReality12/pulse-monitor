import Foundation

public struct Snapshot: Codable, Sendable, Equatable {
    public var date = Date()
    public var cpu: Double?
    public var performanceCPU: Double?
    public var efficiencyCPU: Double?
    public var memoryTotal: UInt64?
    public var memoryUsed: UInt64?
    public var compressed: UInt64?
    public var memoryFreePercent: Double?
    public var pressure: Pressure = .unavailable
    public var swap: UInt64?
    public var thermal = "Unavailable"
    public var temperature: Double?
    public var cpuDieTemperature: Double?
    public var effectiveTemperature: Double? { cpuDieTemperature ?? temperature }
    public var fans: [Double] = []
    public var sensorStatus = "Waiting for sensors"
    /// From `pmset -g therm` sources; nil when macOS has recorded nothing.
    public var cpuSpeedLimit: Int?
    public var thermalWarning: Int?
    public var diskFree: UInt64?
    public var diskTotal: UInt64?
    public var bytesWritten: UInt64?
    public var writesPerSecond: Double?
    public var writtenToday: UInt64?
    public var baselineStatus = "Unavailable"
    public var groups: [ProcessGroup] = []
    public var processCount = 0
    public var limitedProcessCount = 0
    public var processSampleDate: Date?
    public var sensorSampleDate: Date?
    public var topMemoryGroup: String?
    public var swapGrowthTenMinutes: UInt64?
    public var highCPUDuration: TimeInterval = 0
    public init() {}
    public var memoryPercent: Double? {
        guard let used = memoryUsed, let total = memoryTotal, total > 0 else { return nil }
        return Double(used) / Double(total) * 100
    }
    public var diskFreeFraction: Double? {
        guard let free = diskFree, let total = diskTotal, total > 0 else { return nil }
        return Double(free) / Double(total)
    }
    public var signal: HealthSignal {
        if thermal == "Critical" || thermal == "Serious" || (effectiveTemperature.map { $0 >= 95 } ?? false) { return .heat }
        if pressure == .warning || pressure == .critical || (swapGrowthTenMinutes.map { $0 > 1_000_000_000 } ?? false) { return .memory }
        if diskState == .critical || diskState == .warning { return .disk }
        if let cpu, cpu > 85, highCPUDuration >= 30 { return .cpu }
        if pressure == .unavailable || cpu == nil || diskState == .unavailable { return .unavailable }
        return .none
    }
    public var verdict: String { HumanCopy(self).headline }
    public var detail: String {
        let copy = HumanCopy(self)
        return copy.detail + " " + copy.ownerLine
    }
    public var needsAttention: Bool { signal != .none && signal != .unavailable }
    public func hasSameReadings(as other: Self) -> Bool {
        var lhs = self, rhs = other
        lhs.date = .distantPast; rhs.date = .distantPast
        lhs.processSampleDate = nil; rhs.processSampleDate = nil
        lhs.sensorSampleDate = nil; rhs.sensorSampleDate = nil
        return lhs == rhs
    }
}
public enum MetricFormat {
    public static func bytes(_ value: UInt64) -> String {
        if value >= 1_000_000_000 { return String(format: "%.1f GB", Double(value) / 1e9) }
        if value >= 1_000_000 { return String(format: "%.0f MB", Double(value) / 1e6) }
        if value >= 1_000 { return String(format: "%.0f KB", Double(value) / 1e3) }
        return "\(value) B"
    }
    public static func bytes(_ value: UInt64?) -> String { value.map { bytes($0) } ?? "Unavailable" }
    public static func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "Unavailable" }
}


import Foundation

/// Wording shared by the hero and menu; resource uncertainty uses a shared suffix and footnote.
public struct HumanCopy: Sendable, Equatable {
    public static let partialFootnote = "+ = some processes hidden by macOS"
    public let tone: Tone
    public let headline: String
    public let detail: String
    public let ownerLine: String
    public let symbol: String
    public init(_ snapshot: Snapshot) {
        tone = snapshot.healthTone
        let free = snapshot.diskFree.map { MetricFormat.bytes($0) + " left" } ?? "free space unavailable"
        let busiest = snapshot.groups.filter { $0.cpu != nil }.max { ($0.cpu ?? 0) < ($1.cpu ?? 0) }.map(Self.ownerName) ?? "unavailable"
        switch snapshot.signal {
        case .disk:
            headline = snapshot.diskTone == .risk ? "Disk is almost full: \(free)" : "Disk is getting full: \(free)"
            detail = "Review large folders before downloading more."
            symbol = "internaldrive"
        case .heat:
            headline = "Your Mac is running hot"
            let reading = snapshot.effectiveTemperature.map { String(format: "%.0f°C", $0) } ?? snapshot.thermal
            detail = "\(reading). Most CPU: \(busiest)."
            symbol = "thermometer.high"
        case .memory:
            headline = snapshot.pressure == .critical ? "Memory needs attention" : "Memory is tight"
            let growth = snapshot.swapGrowthTenMinutes.flatMap { $0 > 1_000_000_000 ? "Swap grew \(MetricFormat.bytes($0))" : nil }
            detail = "\(growth ?? "\(snapshot.pressure.rawValue) pressure"). Most memory: \(snapshot.topMemoryGroup ?? busiest)."
            symbol = "memorychip"
        case .cpu:
            headline = "Your Mac is working hard"
            detail = "\(MetricFormat.percent(snapshot.cpu)) CPU across all cores. Most CPU: \(busiest)."
            symbol = "cpu"
        case .unavailable:
            headline = "Some readings are unavailable"
            detail = "macOS limits a few readings. Busiest: \(busiest)."
            symbol = "questionmark.circle"
        case .none:
            headline = snapshot.heatLevel == .hot ? "Your Mac is running hot" : "Your Mac is OK"
            let swap = snapshot.swap.map { $0 == 0 ? "No swap in use" : "\(MetricFormat.bytes($0)) swap" } ?? "Swap unavailable"
            detail = "\(swap). Busiest: \(busiest)."
            symbol = snapshot.heatLevel == .hot ? "thermometer.high" : "checkmark.seal"
        }
        if let owner = snapshot.groups.first {
            let amount = owner.resident.map { MetricFormat.bytes($0) + (owner.limited ? "+" : "") } ?? owner.memoryLabel
            ownerLine = "Biggest user: \(Self.ownerName(owner)), \(amount)"
        } else { ownerLine = "Checking what's using your Mac…" }
    }
    public static func ownerName(_ owner: ProcessGroup) -> String {
        guard owner.category == "AI session", let range = owner.title.range(of: " · ") else { return owner.title }
        return String(owner.title[..<range.lowerBound]) + " (" + owner.title[range.upperBound...] + ")"
    }
}

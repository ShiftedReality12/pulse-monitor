import Foundation

public struct DiskEstimate: Sendable, Identifiable, Equatable, Codable {
    public var stale: Bool = false
    public var id: String { path }
    public let path: String
    public let bytes: UInt64?
    public let complete: Bool
    public let date: Date
    public var partitioned: Bool = false
    public var skippedDirectories: Int = 0
    public var status: String { bytes == nil ? "Unavailable, protected or not installed" : complete ? (stale ? "Cached estimate · refreshing · allocated bytes" : "Estimate · allocated bytes") + (skippedDirectories > 0 ? " · unchanged empty folders skipped" : "") : "Partial estimate · limit, protection or permission reached" }
}

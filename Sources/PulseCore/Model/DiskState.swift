import Foundation

public enum DiskState: Sendable {
    case calm, warning, critical, unavailable
    public static func classify(free: UInt64?, total: UInt64?) -> Self {
        guard let free, let total, total > 0, free <= total else { return .unavailable }
        if free < 10_000_000_000 || Double(free) / Double(total) < 0.05 { return .critical }
        // The explicit 32.6 GB calm example governs: warning is absolute headroom.
        if free < 20_000_000_000 { return .warning }
        return .calm
    }
    public var tone: Tone {
        switch self {
        case .calm: .calm
        case .warning: .warm
        case .critical: .risk
        case .unavailable: .unavailable
        }
    }
}
extension Snapshot {
    public var diskState: DiskState { DiskState.classify(free: diskFree, total: diskTotal) }
}

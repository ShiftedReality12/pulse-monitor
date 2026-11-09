import Foundation

public enum Tone: Sendable { case calm, warm, hot, risk, unavailable }

extension HeatLevel {
    public var tone: Tone {
        switch self {
        case .cool: .calm
        case .warm: .warm
        case .hot: .hot
        case .risk: .risk
        case .unavailable: .unavailable
        }
    }
}
extension Snapshot {
    public var heatTone: Tone { heatLevel.tone }
    public var cpuTone: Tone { cpu == nil ? .unavailable : (cpu ?? 0) > 85 ? .warm : .calm }
    public var memoryTone: Tone {
        if pressure == .critical { return .hot }
        if pressure == .warning || (swapGrowthTenMinutes ?? 0) > 1_000_000_000 { return .warm }
        return memoryPercent == nil ? .unavailable : .calm
    }
    public var diskTone: Tone { diskState.tone }
    public var healthTone: Tone {
        switch signal {
        case .heat: heatLevel.tone
        case .memory: memoryTone
        case .cpu: .warm
        case .disk: diskTone
        case .unavailable: .unavailable
        case .none: heatLevel == .unavailable ? .calm : heatLevel.tone
        }
    }
}

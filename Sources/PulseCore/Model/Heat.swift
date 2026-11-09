import Foundation

public enum HeatLevel: String, Sendable {
    case cool = "Cool", warm = "Warm", hot = "Hot", risk = "Throttling risk", unavailable = "Sensor unavailable"
    public static func classify(temperature: Double?, thermal: String) -> Self {
        if thermal == "Serious" || thermal == "Critical" { return .risk }
        guard let temperature, temperature.isFinite else { return thermal == "Warm" ? .warm : .unavailable }
        if temperature >= 95 { return .risk }
        if temperature >= 85 { return .hot }
        if temperature >= 70 || thermal == "Warm" { return .warm }
        return .cool
    }
}
extension Snapshot {
    public var heatLevel: HeatLevel { HeatLevel.classify(temperature: effectiveTemperature, thermal: thermal) }
    public var aiProcessCount: Int { groups.reduce(0) { $0 + $1.aiProcessCount } }
}

import Foundation

public struct TraceCoordinate: Sendable, Equatable {
    public let x: Double
    public let y: Double
}
public enum TraceGeometry {
    public static func timeline(_ points: [PlotPoint], domain: ClosedRange<Double>) -> [TraceCoordinate] {
        let valid = points.filter { $0.value.isFinite }
        guard let first = valid.first, let last = valid.last else { return [] }
        let duration = last.date.timeIntervalSince(first.date)
        let span = max(1, domain.upperBound - domain.lowerBound)
        func coordinate(_ point: PlotPoint, x: Double) -> TraceCoordinate {
            TraceCoordinate(x: min(1, max(0, x)), y: 1 - min(1, max(0, (point.value - domain.lowerBound) / span)))
        }
        guard duration > 0 else { return [coordinate(first, x: 0), coordinate(first, x: 1)] }
        return valid.map { coordinate($0, x: $0.date.timeIntervalSince(first.date) / duration) }
    }
    public static func window(_ points: [PlotPoint], ending: Date, seconds: Double, ceiling: Double) -> [TraceCoordinate] {
        let valid = points.filter { $0.value.isFinite && $0.date <= ending && ending.timeIntervalSince($0.date) <= seconds }
        return valid.map { TraceCoordinate(x: max(0, 1 - ending.timeIntervalSince($0.date) / seconds), y: 1 - min(1, max(0, $0.value / max(1, ceiling)))) }
    }
    public static func readings(_ values: [Double]) -> [TraceCoordinate] {
        let valid = values.filter(\.isFinite), ceiling = max(1, values.filter(\.isFinite).max() ?? 1)
        let points = valid.enumerated().map { TraceCoordinate(x: Double($0.offset) / Double(max(1, valid.count - 1)), y: 1 - min(1, max(0, $0.element / ceiling))) }
        guard let first = points.first, points.count == 1 else { return points }
        return [first, TraceCoordinate(x: 1, y: first.y)]
    }
}

import SwiftUI
import PulseCore

struct HistoryChart: View {
    let points: [PlotPoint]
    let domain: ClosedRange<Double>
    var tint = Color.teal
    var axes = false
    var body: some View {
        let coordinates = TraceGeometry.timeline(points, domain: domain)
        VStack(spacing: axes ? 8 : 0) {
            ZStack(alignment: .bottomLeading) {
                if axes { TraceGrid().stroke(.primary.opacity(0.07), style: StrokeStyle(lineWidth: 0.5, dash: [3, 4])) }
                TraceShape(points: coordinates, filled: true).fill(tint.opacity(points.count > 1 ? 0.14 : 0))
                TraceShape(points: coordinates).stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if points.isEmpty { Text("Collecting readings").font(.caption2).foregroundStyle(.secondary) }
                else if points.count == 1 { Text("First reading").font(.system(size: 8)).foregroundStyle(.secondary) }
            }
            if axes {
                HStack {
                    Text(points.first?.date.formatted(date: .omitted, time: .shortened) ?? "Waiting")
                    Spacer()
                    Text("\(Int(domain.lowerBound))–\(Int(domain.upperBound))")
                    Spacer()
                    Text("Now")
                }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }.transaction { $0.animation = nil; $0.disablesAnimations = true }
            .accessibilityLabel("Measured history, up to one hour; \(points.count) readings")
    }
}
struct TraceShape: Shape {
    let points: [TraceCoordinate]
    var filled = false
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: rect.minX + rect.width * first.x, y: rect.minY + rect.height * first.y))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + rect.width * point.x, y: rect.minY + rect.height * point.y))
        }
        if filled {
            path.addLine(to: CGPoint(x: rect.minX + rect.width * last.x, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * first.x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
struct TraceGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [0.0, 0.5, 1.0] {
            let y = rect.minY + fraction * rect.height
            path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

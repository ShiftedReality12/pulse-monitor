import SwiftUI
import PulseCore

/// Owners whose memory keeps climbing (F2).
struct LeakSection: View {
    let insights: Insights
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("Leak watch").font(.largeTitle.weight(.semibold))
                Text(status).foregroundStyle(.secondary)
                if insights.leaks.isEmpty {
                    ContentUnavailableView(insights.leakHistory < LeakWatch.Policy().minimumSpan ? "Still learning" : "No steady climbs",
                                           systemImage: insights.leakHistory < LeakWatch.Policy().minimumSpan ? "hourglass" : "checkmark.seal",
                                           description: Text(insights.leakHistory < LeakWatch.Policy().minimumSpan
                                                             ? "Leak watch needs 10 minutes of readings before it can call anything a leak."
                                                             : "No app or group has kept growing over the last half hour."))
                }
                ForEach(insights.leaks) { finding in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Label(finding.title, systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.orange)
                            Spacer()
                            Text("+" + MetricFormat.bytes(UInt64(max(0, finding.slopePerHour))) + "/hour").font(.title3.weight(.semibold).monospacedDigit())
                        }
                        Text(finding.explanation)
                        HStack(spacing: 24) {
                            LabeledContent("Now", value: MetricFormat.bytes(finding.current))
                            LabeledContent("Grew", value: "+" + MetricFormat.bytes(finding.growth))
                            LabeledContent("Over", value: "\(Int((finding.span / 60).rounded())) min")
                            LabeledContent("Processes", value: "\(finding.members)")
                        }.font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }.modifier(ContentCard())
                }
                Text("A flag needs at least 10 minutes of steady growth (50 MB or more, over 100 MB/hour) that has not come back down. Memory is summed physical footprint. Pulse only watches; it never quits anything.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
    private var status: String {
        let minutes = Int(insights.leakHistory / 60)
        return "Watching \(insights.leakTracked) apps and groups · \(minutes) min of history · \(insights.leaks.count) flagged"
    }
}

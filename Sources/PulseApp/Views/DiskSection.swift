import SwiftUI
import PulseCore

struct DiskSection: View {
    let snapshot: Snapshot
    let plots: PlotHistory
    let disk: DiskUsageModel
    var insights = Insights()
    private var writers: [ProcessGroup] { snapshot.groups.filter { ($0.writesPerSecond ?? 0) > 0 }.sorted { ($0.writesPerSecond ?? 0) > ($1.writesPerSecond ?? 0) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Your startup disk").font(.largeTitle.weight(.semibold))
                RunwayCard(snapshot: snapshot, insights: insights)
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(MetricFormat.bytes(snapshot.diskFree)) free").font(.system(.largeTitle, design: .rounded).monospacedDigit())
                    Text(snapshot.diskState == .unavailable ? "Capacity unavailable" : snapshot.diskState == .calm ? "Room available for your next task." : "Space is low. Review large folders before downloading more.").foregroundStyle(.secondary)
                    DiskBreakdownView(snapshot: snapshot, disk: disk)
                    HStack {
                        Text("Used \(MetricFormat.bytes(used))")
                        Spacer()
                        Text("Free \(MetricFormat.bytes(snapshot.diskFree))")
                    }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    LabeledContent("Written since boot", value: MetricFormat.bytes(snapshot.bytesWritten))
                    LabeledContent("Writing now", value: snapshot.writesPerSecond.map { MetricFormat.bytes(UInt64(max(0, $0))) + "/s" } ?? "Unavailable")
                    LabeledContent("Since first reading today", value: MetricFormat.bytes(snapshot.writtenToday))
                }.modifier(ContentCard())
                HistoryChart(points: plots.disk, domain: 0...max(1, Double(snapshot.diskTotal ?? 1)), tint: snapshot.diskTone.color, axes: true).frame(height: 140)
                Text("Writing right now").font(.title3.weight(.semibold))
                ForEach(Array(writers.prefix(5))) { OwnerDisclosure(group: $0) }
                if writers.isEmpty { Text("No positive owner write rates are readable in this sample.").foregroundStyle(.secondary) }
                Text("Known space users · estimates").font(.title3.weight(.semibold))
                Text("Allocated bytes in selected folders; partial scans are lower bounds. APFS sharing and other folders can change physical totals. Cached for five minutes.").font(.caption).foregroundStyle(.secondary)
                if disk.loading { Text("Measuring selected folders…").foregroundStyle(.secondary) }
                ForEach(disk.estimates) { estimate in
                    VStack(alignment: .leading, spacing: 5) {
                        LabeledContent(estimate.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path + "/", with: "~/"), value: (estimate.bytes != nil && !estimate.complete ? "at least " : "") + MetricFormat.bytes(estimate.bytes))
                        Text(estimate.status + " · " + estimate.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                }
                Text("Writes cover readable storage-driver counters, including removable devices; they do not measure SSD wear. No automatic deletion.").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
    private var used: UInt64? {
        guard let total = snapshot.diskTotal, let free = snapshot.diskFree else { return nil }
        return total >= free ? total - free : nil
    }
}

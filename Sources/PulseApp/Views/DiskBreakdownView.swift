import SwiftUI
import PulseCore

struct DiskBreakdownView: View {
    let snapshot: Snapshot
    let disk: DiskUsageModel
    var compact = false
    private var buckets: [DiskBucket] { DiskBreakdown.buckets(estimates: disk.estimates, sessions: snapshot.groups) }
    private let colours: [Color] = [.teal, .blue, .purple]
    private func colour(_ segment: DiskSegment, index: Int) -> Color {
        segment.id == "free" ? .primary.opacity(0.12) : ["other", "protected"].contains(segment.id) ? .secondary.opacity(0.45) : colours[index % colours.count]
    }
    var body: some View {
        let composition = DiskComposition(snapshot: snapshot, buckets: buckets, fullDiskAccess: disk.fullDiskAccess)
        let _ = RenderDiagnostics.shared.captureDisk(buckets)
        let _ = RenderDiagnostics.shared.captureComposition(composition)
        VStack(alignment: .leading, spacing: compact ? 4 : 7) {
            Text(composition.summary).font(.system(size: compact ? 10 : 12)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if composition.total > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(Array(composition.segments.enumerated()), id: \.element.id) { index, segment in
                            Rectangle().fill(colour(segment, index: index))
                                .frame(width: geometry.size.width * Double(segment.bytes) / Double(composition.total))
                        }
                    }
                }.frame(height: compact ? 8 : 10)
                ForEach(Array(composition.segments.enumerated()), id: \.element.id) { index, segment in
                    HStack(spacing: 5) {
                        Circle().fill(colour(segment, index: index)).frame(width: 5, height: 5)
                        Text(segment.label + (segment.partial ? segment.id == "protected" ? " (estimate)" : " (partial)" : "")).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(MetricFormat.bytes(segment.bytes)).monospacedDigit()
                    }.font(.system(size: compact ? 9 : 10)).foregroundStyle(.secondary)
                }
            }
            Text(disk.loading ? "Measuring folders…" : disk.estimates.contains(where: \.stale) ? "Cached totals · refreshing folders…" : buckets.isEmpty ? "Folder sizes unavailable" : "Folders & AI projects · estimates")
                .font(.system(size: compact ? 9 : 10)).foregroundStyle(.secondary)
            Text(disk.accessHint).fixedSize(horizontal: false, vertical: true)
                .font(.system(size: compact ? 9 : 10)).foregroundStyle(.secondary)
        }.help("Selected allocated-byte estimates within used capacity. Other measured contains folders outside the top segments. Protected by macOS = used minus measured; an upper bound including all unmeasured use, not a protected-folder measurement. Symlinks are skipped; protected trees require Full Disk Access. Root totals exclude separately measured nested roots and node_modules. Partial estimates are lower bounds; shared files affect totals.")
    }
}

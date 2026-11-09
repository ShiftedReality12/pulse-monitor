import Foundation

/// Residual use is an upper-bound estimate, never a measurement of protected folders.
public struct DiskSegment: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let bytes: UInt64
    public let partial: Bool
}
public struct DiskComposition: Sendable {
    public let segments: [DiskSegment]
    public let total: UInt64
    public let summary: String
    public init(snapshot: Snapshot, buckets: [DiskBucket], folderLimit: Int = 8, fullDiskAccess: Bool = false) {
        guard let capacity = snapshot.diskTotal, let free = snapshot.diskFree,
              capacity > 0, free <= capacity else {
            segments = []; total = 0; summary = "Capacity unavailable"; return
        }
        total = capacity
        let used = capacity - free
        summary = "\(MetricFormat.bytes(used)) used · \(MetricFormat.bytes(free)) free"
        let sorted = buckets.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
        let selected = Array(sorted.prefix(max(0, folderLimit)))
        var remaining = used, result: [DiskSegment] = []
        let measured = buckets.reduce(UInt64(0)) { min(used, $0 + min(used - $0, $1.bytes)) }
        let hiddenMeasured = measured - min(measured, selected.reduce(UInt64(0)) { min(measured, $0 + min(measured - $0, $1.bytes)) })
        for bucket in selected {
            let amount = min(remaining, bucket.bytes)
            guard amount > 0 else { continue }
            result.append(DiskSegment(id: bucket.id, label: bucket.label, bytes: amount, partial: bucket.partial))
            remaining -= amount
        }
        let other = min(remaining, hiddenMeasured)
        result.append(DiskSegment(id: "other", label: "Other measured", bytes: other, partial: false))
        result.append(DiskSegment(id: "protected", label: fullDiskAccess ? "Unmeasured" : "Protected by macOS", bytes: remaining - other, partial: true))
        result.append(DiskSegment(id: "free", label: "Free", bytes: free, partial: false))
        segments = result.filter { $0.bytes > 0 }
    }
}

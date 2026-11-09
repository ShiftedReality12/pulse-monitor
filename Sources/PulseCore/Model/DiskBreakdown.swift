import Foundation

public struct DiskBucket: Sendable, Identifiable, Equatable {
    public var id: String { path }
    public let path: String
    public let label: String
    public let bytes: UInt64
    public let partial: Bool
    public let isProject: Bool
}
/// Selected allocated-byte estimates, not a claim to reconcile APFS capacity accounting.
public enum DiskBreakdown {
    private static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs.hasPrefix(rhs + "/") || rhs.hasPrefix(lhs + "/")
    }
    /// `/tmp` and `/private/tmp` are the same folder. Project matching uses one form.
    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
    public static func projectPaths(_ sessions: [ProcessGroup]) -> [String] {
        let broadRoots: Set<String> = ["/", "/Users", "/Volumes", "/Applications", "/Library", "/System", "/private", "/tmp", "/var", FileManager.default.homeDirectoryForCurrentUser.path]
        let paths = sessions.filter { $0.category == "AI session" }.compactMap(\.cwd)
            .filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { !broadRoots.contains($0) && !($0.hasPrefix("/Volumes/") && $0.split(separator: "/").count == 2) }
        var result: [String] = []
        for path in Set(paths).sorted(by: { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }) {
            if !result.contains(where: { overlaps($0, path) }) { result.append(path) }
            if result.count == 3 { break }
        }
        return result
    }
    public static func roots(sessions: [ProcessGroup]) -> [URL] {
        let projects = projectPaths(sessions)
        let folders = DiskEstimates.defaultRoots
        let paths = (folders + projects.map { URL(fileURLWithPath: $0) }).map { $0.standardizedFileURL.path }
        return Set(paths).sorted().map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
    public static func buckets(estimates: [DiskEstimate], sessions: [ProcessGroup]) -> [DiskBucket] {
        let projects = Set(projectPaths(sessions))
        var selected: [DiskBucket] = []
        let sorted = estimates.sorted {
            let a = projects.contains(canonical($0.path)), b = projects.contains(canonical($1.path))
            if a != b { return a }
            return ($0.bytes ?? 0) > ($1.bytes ?? 0)
        }
        for estimate in sorted {
            guard let bytes = estimate.bytes, bytes > 0, !selected.contains(where: { overlaps($0.path, estimate.path) && !estimate.partitioned }) else { continue }
            let project = projects.contains(canonical(estimate.path))
            let name = estimate.path == DiskRootPlan.nodes ? "node_modules" : URL(fileURLWithPath: estimate.path).lastPathComponent
            selected.append(DiskBucket(path: estimate.path, label: project ? "AI · \(name)" : name,
                                       bytes: bytes, partial: !estimate.complete, isProject: project))
        }
        return selected
    }
}

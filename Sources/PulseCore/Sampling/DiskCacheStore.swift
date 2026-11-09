import Foundation

struct DiskCacheSnapshot: Codable {
    var version = 2
    var home: String
    var granted: Bool
    var exclusions: Set<String>
    var cursors: [String: DiskCursorState]
    var completed: [String: DiskEstimate]? = nil
    var estimates: [String: DiskEstimate]? = nil
    var completedNodes: [String: UInt64]? = nil
}
/// Bounded, versioned checkpoints; writes replace atomically and never exceed one per 30s.
struct DiskCacheStore {
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Pulse/disk-cache.json")
    }
    let url: URL?
    private var lastWrite = -Double.infinity
    var writeDelay: Double { max(0, 30 - (ProcessInfo.processInfo.systemUptime - lastWrite)) }
    init(url: URL?) { self.url = url }
    mutating func read(home: String) -> DiskCacheSnapshot? {
        guard let url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 256 * 1024, let data = try? Data(contentsOf: url), data.count <= 256 * 1024,
              let saved = try? JSONDecoder().decode(DiskCacheSnapshot.self, from: data),
              saved.version == 2, saved.home == home, saved.cursors.count <= 256,
              saved.cursors.allSatisfy({ path, state in
                  path.hasPrefix("/") && state.frames.count <= 128 && state.hardlinks.count <= 4096 && state.entries >= 0 &&
                  state.frames.allSatisfy { $0.path == path || $0.path.hasPrefix(path + "/") } &&
                  state.frames.allSatisfy { $0.offset >= 0 && $0.skipped >= 0 && $0.skipped <= 8192 && $0.signature.count == 6 }
              }) else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        lastWrite = ProcessInfo.processInfo.systemUptime - max(0, Date().timeIntervalSince(modified))
        return saved
    }
    mutating func write(_ snapshot: DiskCacheSnapshot, now: Double = ProcessInfo.processInfo.systemUptime) {
        guard let url, now - lastWrite >= 30 else { return }
        // Check attempts too: failed writes must not spin on a denied filesystem.
        lastWrite = now
        var bounded = snapshot
        // Empty-folder acceleration is optional; progress and totals take precedence over it.
        var data = try? JSONEncoder().encode(bounded)
        if (data?.count ?? Int.max) > 256 * 1024 {
            for path in bounded.cursors.keys { bounded.cursors[path]?.emptyDirectories = [:] }
            data = try? JSONEncoder().encode(bounded)
        }
        guard let data, data.count <= 256 * 1024 else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch { /* Persistence is optional when storage is unavailable; never prompt. */ }
    }
}

import Foundation
import Darwin

struct DiskRootPlan {
    static let derived = "Library/Developer/Xcode/DerivedData"
    static let docker = "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
    static let nodes = "pulse:node_modules"
    static func omitted(home: URL) -> Set<String> { [home.appendingPathComponent(".Trash").path] }
    /// Test trees under `.build/` must not become Disk card rows in the real cache.
    static func isTestFixture(_ path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent
        if name.hasPrefix("disk-fixture-") || name.hasPrefix("v56-disk-") || name.hasPrefix("v57-disk-") || name.hasPrefix("v58-budget-") { return true }
        return path.contains("/.build/disk-fixture-") || path.contains("/.build/v56-disk-") || path.contains("/.build/v57-disk-") || path.contains("/.build/v58-budget-")
    }
    static func isOmitted(_ path: String, home: URL) -> Bool {
        var path = ProtectedPaths.normalized(path).lowercased()
        if path.hasPrefix("/system/volumes/data/") { path = String(path.dropFirst("/system/volumes/data".count)) }
        let trash = home.appendingPathComponent(".Trash").path.lowercased()
        return path == trash || path.hasPrefix(trash + "/")
    }
    static func candidates(home: URL) -> [(URL, URL)] {
        var values = [".claude", ".codex", ".cache", ".npm", ".yarn", ".bun", ".cargo",
                      ".ollama/models", ".lmstudio/models", derived].map { home.appendingPathComponent($0) }.map { ($0, $0) }
        if home == FileManager.default.homeDirectoryForCurrentUser {
            let brew = URL(fileURLWithPath: "/opt/homebrew")
            values += [(brew, brew), (URL(fileURLWithPath: "/usr/local/Homebrew"), URL(fileURLWithPath: "/usr/local"))]
        }
        return values
    }
    static func defaults(home: URL, policy: ProtectedPaths? = nil, budget: DiskScanBudget = DiskScanBudget()) -> [URL] {
        DiskRootDiscovery().scanDefaults(home: home, policy: policy ?? ProtectedPaths(home: home.path), budget: budget).roots
    }
    static func discover(home: URL, policy: ProtectedPaths, budget: DiskScanBudget) -> [URL] { discovery(home: home, policy: policy, budget: budget).roots }
    static func discovery(home: URL, policy: ProtectedPaths, budget: DiskScanBudget) -> (roots: [URL], complete: Bool) {
        DiskRootDiscovery().scanHome(home: home, policy: policy, budget: budget)
    }
    static func dockerSize(home: URL, policy: ProtectedPaths, budget: DiskScanBudget) -> DiskEstimate {
        let path = home.appendingPathComponent(docker)
        let parent = path.deletingLastPathComponent()
        guard budget.take(), let fd = policy.openDirectory(parent.path, budget: budget) else {
            return DiskEstimate(path: path.path, bytes: nil, complete: false, date: Date())
        }
        defer { close(fd) }
        policy.willAccess(path.path)
        var info = stat()
        let valid = fstatat(fd, path.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0 && info.st_mode & S_IFMT == S_IFREG
        return DiskEstimate(path: path.path, bytes: valid ? UInt64(max(0, info.st_blocks)) * 512 : nil, complete: valid, date: Date(), partitioned: true)
    }
}

import Foundation
import Darwin

/// One small home iterator plus a candidate index survive small CPU slices.
final class DiskRootDiscovery {
    private var directory: UnsafeMutablePointer<DIR>?
    private var homeDevice: dev_t = 0
    private var homeRoots: [URL] = []
    private var installed: [URL] = []
    private var candidateIndex = 0
    private(set) var homeComplete = false
    private(set) var defaultsComplete = false
    var openDescriptors: Int { directory == nil ? 0 : 1 }
    deinit { if let directory { closedir(directory) } }
    func resetHome() {
        if let directory { closedir(directory) }; directory = nil
        homeRoots = []; homeComplete = false
    }
    func resetDefaults() { installed = []; candidateIndex = 0; defaultsComplete = false }
    func scanHome(home: URL, policy: ProtectedPaths, budget: DiskScanBudget) -> (roots: [URL], complete: Bool) {
        if homeComplete { return (homeRoots, true) }
        if directory == nil {
            guard let fd = policy.openDirectory(home.path, budget: budget) else { return (homeRoots, false) }
            var info = stat()
            guard fstat(fd, &info) == 0, let stream = fdopendir(fd) else { close(fd); return (homeRoots, false) }
            homeDevice = info.st_dev; directory = stream
        }
        guard let directory else { return (homeRoots, false) }
        while budget.take() {
            errno = 0
            guard let entry = readdir(directory) else {
                homeComplete = errno == 0; closedir(directory); self.directory = nil
                return (homeRoots, homeComplete)
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            let path = home.appendingPathComponent(name)
            guard !DiskRootPlan.isOmitted(path.path, home: home), policy.allows(path.path) else { continue }
            policy.willAccess(path.path)
            var info = stat()
            if fstatat(dirfd(directory), name, &info, AT_SYMLINK_NOFOLLOW) == 0,
               info.st_mode & S_IFMT == S_IFDIR, info.st_dev == homeDevice { homeRoots.append(path) }
        }
        return (homeRoots, false)
    }
    func scanDefaults(home: URL, policy: ProtectedPaths, budget: DiskScanBudget) -> (roots: [URL], complete: Bool) {
        let candidates = DiskRootPlan.candidates(home: home)
        while candidateIndex < candidates.count, budget.available {
            let (probe, output) = candidates[candidateIndex]
            if let fd = policy.openDirectory(probe.path, budget: budget) { close(fd); installed.append(output); candidateIndex += 1 }
            else if budget.available { candidateIndex += 1 }
        }
        defaultsComplete = candidateIndex == candidates.count
        return (installed, defaultsComplete)
    }
}

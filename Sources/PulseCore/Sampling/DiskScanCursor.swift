import Foundation
import Darwin

struct DiskCursorState: Codable {
    var frames: [DiskDirectoryState]
    var hardlinks: Set<UInt64>
    var started: Bool, failed: Bool, finished: Bool
    var bytes: UInt64?
    var nodeBytes: UInt64
    var date: Date
    var entries: Int
    var emptyDirectories: [String: [Int64]]
    var rootSignature: [Int64]? = nil
}
/// Actor-owned DFS; stable directory cookies and batch positions survive relaunches.
final class DiskScanCursor {
    private var stack: [DiskDirectory] = []
    private var restore: [DiskDirectoryState] = []
    private(set) var rootSignature: [Int64]?
    private var hardlinks = Set<UInt64>()
    private var started = false, failed = false
    var openDescriptors: Int { stack.reduce(0) { $0 + ($1.fd >= 0 ? 1 : 0) } }
    private(set) var entries = 0
    private(set) var finished = false
    private(set) var bytes: UInt64?
    private(set) var nodeBytes: UInt64 = 0
    private(set) var date = Date()
    private(set) var emptyDirectories: [String: [Int64]]
    private(set) var skippedDirectories = 0
    init(emptyDirectories: [String: [Int64]] = [:]) { self.emptyDirectories = emptyDirectories }
    init(state: DiskCursorState) {
        rootSignature = state.rootSignature
        restore = state.frames; hardlinks = state.hardlinks; started = state.started
        failed = state.failed; finished = state.finished; bytes = state.bytes
        nodeBytes = state.nodeBytes; date = state.date; entries = state.entries
        emptyDirectories = state.emptyDirectories
    }
    var state: DiskCursorState {
        DiskCursorState(frames: restore.isEmpty ? stack.map { $0.checkpoint() } : restore, hardlinks: hardlinks,
                        started: started, failed: failed, finished: finished, bytes: bytes,
                        nodeBytes: nodeBytes, date: date, entries: entries, emptyDirectories: emptyDirectories, rootSignature: rootSignature)
    }
    private func trimHandles() {
        var excess = openDescriptors - 11
        guard excess > 0 else { return }
        for frame in stack where frame.fd >= 0 && excess > 0 { frame.suspend(); excess -= 1 }
    }
    private func append(fd: Int32, path: String, nodes: Bool, policy: ProtectedPaths, signature: [Int64]? = nil, uniform: Bool = false) {
        guard let frame = DiskDirectory(fd: fd, path: path, nodes: nodes, policy: policy, prepared: signature, sensitiveOverride: uniform ? false : nil) else { failed = true; return }
        if emptyDirectories[path] == frame.state.signature { skippedDirectories += 1; return }
        stack.append(frame)
    }
    func suspend() {
        if !stack.isEmpty { restore = stack.map { $0.checkpoint() }; stack = [] }
    }
    func advance(path: String, policy: ProtectedPaths, budget: DiskScanBudget,
                 slice: DiskScanBudget, excluding: Set<String>, expectedDevice: Int64? = nil, keepOpen: Bool = false) -> DiskEstimate {
        let uniform = DiskDirectory.uniformPolicy(path) && policy.allows(path + "/Music")
        defer { if !keepOpen || budget.cancellation?.cancelled == true { suspend() } }
        if !restore.isEmpty {
            for saved in restore {
                trimHandles()
                guard let fd = policy.openDirectory(saved.path, budget: budget),
                      let frame = DiskDirectory(fd: fd, path: saved.path, nodes: saved.nodes, policy: policy, saved: saved, sensitiveOverride: uniform ? false : nil) else {
                    stack = []; started = false; finished = false; bytes = nil; nodeBytes = 0
                    hardlinks = []; entries = 0; failed = false; break
                }
                stack.append(frame)
            }
            restore = []
        }
        if !started, budget.available, slice.available {
            started = true; bytes = 0
            if let fd = policy.openDirectory(path, budget: budget) {
                guard DiskDirectory.isLocal(fd), expectedDevice == nil || DiskDirectory.signature(fd)?.first == expectedDevice else { close(fd); failed = true; finished = true; return DiskEstimate(path: path, bytes: nil, complete: false, date: date) }
                rootSignature = DiskDirectory.signature(fd)
                append(fd: fd, path: path, nodes: path.hasSuffix("/node_modules"), policy: policy, signature: rootSignature, uniform: uniform)
            } else {
                bytes = nil
                if budget.available && slice.available { failed = true } else { started = false }
            }
        }
        while budget.available && slice.available, let frame = stack.last {
            if frame.fd < 0 {
                trimHandles()
                guard let fd = policy.openDirectory(frame.state.path, budget: budget),
                      let opened = DiskDirectory(fd: fd, path: frame.state.path, nodes: frame.state.nodes, policy: policy,
                                                 saved: frame.state, sensitiveOverride: uniform ? false : nil) else {
                    if budget.available { failed = true; stack.removeLast() }; continue
                }
                stack[stack.count - 1] = opened; continue
            }
            let limit = min(2048, budget.remaining, slice.remaining)
            guard limit > 0 else { break }
            let (allocated, count, ended, boundary) = frame.read(limit: limit, cpuDeadline: budget.nativeCPUDeadline, cancellation: budget.cancellation, policy: policy, excluding: excluding)
            budget.charge(max(1, count)); if budget !== slice { slice.charge(max(1, count)) }
            entries += count
            if frame.state.nodes { nodeBytes += allocated } else { bytes = (bytes ?? 0) + allocated }
            if ended {
                if !frame.state.seen && emptyDirectories.count < 512 { emptyDirectories[frame.state.path] = frame.state.signature }
                stack.removeLast(); continue
            }
            guard let (name, type, inode, links, size, error) = boundary else { continue }
            if error { failed = true; if name.isEmpty { stack.removeLast() }; continue }
            let child = frame.state.path + "/" + name
            if excluding.contains(child) { continue }
            if !frame.sensitive { policy.willAccess(child) }
            let nodes = frame.state.nodes || name == "node_modules"
            if type == 2 {
                guard (uniform || policy.allows(child)), stack.count < 128 else { failed = true; continue }
                trimHandles()
                let fd = openat(frame.fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
                guard fd >= 0 else { failed = true; continue }
                guard let signature = DiskDirectory.signature(fd), signature.first == stack.first?.state.signature.first else { close(fd); continue }
                append(fd: fd, path: child, nodes: nodes, policy: policy, signature: signature, uniform: uniform)
            } else if type == 5 {
                var info = stat()
                if fstatat(frame.fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
                    let allocated = UInt64(max(0, info.st_blocks)) * 512
                    if nodes { nodeBytes += allocated } else { bytes = (bytes ?? 0) + allocated }
                } else { failed = true }
            } else if type == 1 {
                if links > 1 {
                    guard hardlinks.count < 4096 else { failed = true; continue }
                    guard hardlinks.insert(inode).inserted else { continue }
                }
                if nodes { nodeBytes += size } else { bytes = (bytes ?? 0) + size }
            }
            // Symlinks and other non-regular entries are intentional physical-traversal exclusions.
        }
        if started && stack.isEmpty { finished = true }
        date = Date()
        return DiskEstimate(path: path, bytes: bytes, complete: finished && !failed, date: date, partitioned: true, skippedDirectories: skippedDirectories)
    }
}

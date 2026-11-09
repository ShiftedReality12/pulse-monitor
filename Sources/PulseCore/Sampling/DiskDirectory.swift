import Foundation
import Darwin
import CSensors

struct DiskDirectoryState: Codable {
    var path: String
    var nodes: Bool
    var signature: [Int64]
    var offset: Int64 = 0
    var skipped: Int = 0
    var seen = false
}
/// Descriptor-relative physical traversal. Bulk metadata is used only below policy-safe parents.
final class DiskDirectory {
    private var ownsFD = true
    private(set) var fd: Int32
    var state: DiskDirectoryState
    let sensitive: Bool
    private var bulk: OpaquePointer?
    private var batchSafe: Bool?
    private var directory: UnsafeMutablePointer<DIR>?
    static func uniformPolicy(_ path: String) -> Bool {
        var value = ProtectedPaths.normalized(path).lowercased()
        if value.hasPrefix("/system/volumes/data/") { value = String(value.dropFirst("/system/volumes/data".count)) }
        let parts = value.split(separator: "/")
        return !parts.isEmpty && !(parts.first == "users" && parts.count <= 2)
    }
    static func isLocal(_ fd: Int32) -> Bool {
        var fs = statfs()
        return fstatfs(fd, &fs) == 0 && fs.f_flags & UInt32(MNT_LOCAL) != 0
    }
    static func signature(_ fd: Int32) -> [Int64]? {
        var info = stat()
        guard fstat(fd, &info) == 0 else { return nil }
        return [Int64(info.st_dev), Int64(bitPattern: info.st_ino), Int64(info.st_mtimespec.tv_sec),
                Int64(info.st_mtimespec.tv_nsec), Int64(info.st_ctimespec.tv_sec), Int64(info.st_ctimespec.tv_nsec)]
    }
    init?(fd: Int32, path: String, nodes: Bool, policy: ProtectedPaths, saved: DiskDirectoryState? = nil, prepared: [Int64]? = nil, sensitiveOverride: Bool? = nil) {
        guard let signature = prepared ?? Self.signature(fd), saved == nil || saved?.signature == signature else { close(fd); return nil }
        self.fd = fd
        sensitive = sensitiveOverride ?? !policy.allows(path + "/Music")
        state = saved ?? DiskDirectoryState(path: path, nodes: nodes, signature: signature)
        if sensitive {
            directory = fdopendir(fd)
            guard let directory else { close(fd); ownsFD = false; return nil }
            if let saved {
                guard saved.offset == 0 else { closedir(directory); self.directory = nil; ownsFD = false; return nil }
                for _ in 0..<saved.skipped { guard readdir(directory) != nil else { break } }
            }
        } else {
            bulk = pulse_bulk_open(fd, state.offset, Int32(state.skipped))
            guard bulk != nil else { close(fd); ownsFD = false; return nil }
        }
    }
    deinit { if let bulk { pulse_bulk_close(bulk) }; if let directory { closedir(directory) } else if ownsFD { close(fd) } }
    func suspend() {
        guard fd >= 0 else { return }
        state = checkpoint()
        if let bulk { pulse_bulk_close(bulk); self.bulk = nil }
        if let directory { closedir(directory); self.directory = nil } else { close(fd) }
        fd = -1; ownsFD = false
    }
    func checkpoint() -> DiskDirectoryState {
        var result = state
        if let bulk { result.offset = pulse_bulk_offset(bulk); result.skipped = Int(pulse_bulk_skipped(bulk)) }
        if directory != nil { result.offset = 0; result.skipped = state.skipped }
        return result
    }
    func read(limit: Int, cpuDeadline: Double, cancellation: ScanCancellation?, policy: ProtectedPaths, excluding: Set<String>) -> (UInt64, Int, Bool, (String, UInt32, UInt64, UInt32, UInt64, Bool)?) {
        if batchSafe == nil {
            let prefix = state.path + "/"
            batchSafe = !excluding.contains { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") }
        }
        if let bulk, batchSafe == true {
            var batch = PulseDiskBatch()
            pulse_bulk_batch(bulk, Int32(limit), &batch, cancellation?.pointer, cpuDeadline)
            state.seen = state.seen || batch.entries > 0
            let boundary: (String, UInt32, UInt64, UInt32, UInt64, Bool)?
            if batch.status == 2 {
                let name = withUnsafePointer(to: &batch.boundary.name) { $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) } }
                let e = batch.boundary
                boundary = (name, e.type, e.inode, e.links, e.allocated, e.error != 0)
            } else { boundary = batch.status == -1 ? ("", 0, 0, 0, 0, true) : nil }
            return (batch.allocated, Int(batch.entries), batch.status == 0, boundary)
        }
        let item = next(policy: policy, excluding: excluding)
        return (0, item == nil ? 0 : 1, item == nil, item)
    }
    func next(policy: ProtectedPaths, excluding: Set<String>) -> (String, UInt32, UInt64, UInt32, UInt64, Bool)? {
        if let bulk {
            var entry = PulseDiskEntry()
            let count = pulse_bulk_next(bulk, &entry)
            guard count > 0 else { return count < 0 ? ("", 0, 0, 0, 0, true) : nil }
            let name = withUnsafePointer(to: &entry.name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) }
            }
            state.seen = true
            return (name, entry.type, entry.inode, entry.links, entry.allocated, entry.error != 0)
        }
        guard let directory else { return nil }
        while true {
            errno = 0
            guard let entry = readdir(directory) else { return errno == 0 ? nil : ("", 0, 0, 0, 0, true) }
            state.skipped += 1
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            state.seen = true
            let path = state.path + "/" + name
            if name.lowercased() == ".trash" || excluding.contains(path) { return (name, 5, 0, 0, 0, false) }
            guard policy.allows(path) else { return (name, 0, 0, 0, 0, true) }
            policy.willAccess(path)
            var info = stat()
            guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { return (name, 0, 0, 0, 0, true) }
            let type: UInt32 = info.st_mode & S_IFMT == S_IFDIR ? 2 : info.st_mode & S_IFMT == S_IFREG ? 1 : 5
            return (name, type, info.st_ino, UInt32(info.st_nlink), UInt64(max(0, info.st_blocks)) * 512, false)
        }
    }
}

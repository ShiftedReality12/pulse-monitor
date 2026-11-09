import Foundation
import Darwin

/// Protected trees are gated by a silent FDA result; DerivedData alone is allowlisted.
/// A symlink prefix such as `/tmp` is resolved so the named root can be opened. Children are never followed through a symlink.
public struct ProtectedPaths: Sendable {
    public static let shared = ProtectedPaths()
    private let home: String
    private let fullDiskAccess: Bool
    private let observer: @Sendable (String) -> Void
    private let names: Set<String> = ["music", "pictures", "movies", "library", "desktop", "documents", "downloads"]
    public init(home: String = FileManager.default.homeDirectoryForCurrentUser.path, fullDiskAccess: Bool = false,
                observer: @escaping @Sendable (String) -> Void = { _ in }) {
        self.observer = observer
        self.fullDiskAccess = fullDiskAccess
        self.home = Self.normalized(home).lowercased()
    }
    static func normalized(_ path: String) -> String {
        var parts: [String] = []
        for part in path.split(separator: "/") {
            if part == ".." { if !parts.isEmpty { parts.removeLast() } }
            else if part != "." { parts.append(String(part)) }
        }
        return "/" + parts.joined(separator: "/")
    }
    public func allows(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        var path = Self.normalized(path).precomposedStringWithCanonicalMapping.lowercased()
        if path.hasPrefix("/system/volumes/data/") { path = String(path.dropFirst("/system/volumes/data".count)) }
        if ["/volumes", "/network", "/net"].contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return false }
        if path.hasPrefix(home + "/"), let first = path.dropFirst(home.count + 1).split(separator: "/").first,
           names.contains(String(first)) {
            let derived = home + "/library/developer/xcode/deriveddata"
            if path == derived || path.hasPrefix(derived + "/") { return true }
            return fullDiskAccess
        }
        let parts = path.split(separator: "/")
        if parts.count >= 3, parts[0] == "users", names.contains(String(parts[2])) { return false }
        return true
    }
    func willAccess(_ path: String) { observer(path) }
    /// Walk from / using descriptors. A symlink in the middle of the named root is resolved once. The last component and every child stay unfollowed.
    func openDirectory(_ path: String, budget: DiskScanBudget) -> Int32? {
        let path = Self.normalized(path)
        guard allows(path), budget.available else { return nil }
        return openResolved(path, budget: budget, hops: 0)
    }
    private func openResolved(_ path: String, budget: DiskScanBudget, hops: Int) -> Int32? {
        guard hops < 8, allows(path) else { return nil }
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        var prefix = ""
        for (index, part) in parts.enumerated() {
            prefix += "/" + part
            guard budget.available else { close(descriptor); return nil }
            willAccess(prefix)
            let next = openat(descriptor, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
            if next >= 0 { close(descriptor); descriptor = next; continue }
            var info = stat()
            let linked = fstatat(descriptor, part, &info, AT_SYMLINK_NOFOLLOW) == 0 && info.st_mode & S_IFMT == S_IFLNK
            guard linked, index < parts.count - 1 else { close(descriptor); return nil }
            var storage = [CChar](repeating: 0, count: Int(PATH_MAX))
            let length = readlinkat(descriptor, part, &storage, storage.count)
            close(descriptor)
            guard length > 0, length < storage.count else { return nil }
            let target = String(decoding: storage.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let parent = URL(fileURLWithPath: prefix).deletingLastPathComponent().path
            let rest = parts[(index + 1)...].joined(separator: "/")
            let joined = target.hasPrefix("/") ? target + "/" + rest : parent + "/" + target + "/" + rest
            return openResolved(Self.normalized(joined), budget: budget, hops: hops + 1)
        }
        return descriptor
    }
}

import Foundation

/// A missing start identity never certifies an ancestry edge, even when the path matches.
enum ProcessIdentity {
    static func chain(_ process: ProcessSample, byPID: [Int32: ProcessSample]) -> (members: [ProcessSample], limited: Bool) {
        var structural = Set<Int32>(), cursor: ProcessSample? = process
        while let p = cursor {
            guard structural.insert(p.pid).inserted, structural.count <= 64 else { return ([process], true) }
            cursor = byPID[p.parent]
        }
        var result = [process], current = process
        while let parent = byPID[current.parent] {
            guard current.identity > 0, parent.identity > 0, parent.identity <= current.identity else { return (result, true) }
            result.append(parent); current = parent
        }
        return (result, process.identity == 0)
    }
    static func canonical(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.path }
    static func executable(_ process: ProcessSample) -> String {
        process.path.isEmpty ? "name:\(process.name)" : "path:\(canonical(process.path))"
    }
    static func bundlePath(_ path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return canonical(String(path[...range.lowerBound]) + "app")
    }
    static func safeTitle(_ name: String, path: String, pid: Int32) -> String {
        func usable(_ value: String) -> Bool {
            !value.isEmpty && value.range(of: #"^Process [0-9]+$"#, options: .regularExpression) == nil
        }
        if usable(name) { return name }
        let base = path.isEmpty ? "" : URL(fileURLWithPath: path).lastPathComponent
        if usable(base) { return base }
        return path.isEmpty ? "Unknown helper (pid \(pid))" : "Command-line tool in \(URL(fileURLWithPath: path).deletingLastPathComponent().path)"
    }
}

import Foundation

/// Only immutable classification is cached. Parent, cwd, resources and ownership stay live.
struct ProcessMetadataCache {
    private struct Key: Hashable { let pid: Int32; let start: UInt64; let path: String }
    private struct Entry { let name: String; let value: ProcessMetadata }
    private var entries: [Key: Entry] = [:]
    private(set) var hits = 0
    private(set) var misses = 0
    var count: Int { entries.count }
    mutating func prepare(_ processes: [ProcessSample]) -> [Int32: ProcessMetadata] {
        var next: [Key: Entry] = [:], result: [Int32: ProcessMetadata] = [:]
        next.reserveCapacity(processes.count); result.reserveCapacity(processes.count)
        for process in processes {
            let key = Key(pid: process.pid, start: process.identity, path: process.path)
            let entry: Entry
            if process.identity > 0, let old = entries[key], old.name == process.name {
                entry = old; hits += 1
            } else {
                entry = Entry(name: process.name, value: ProcessMetadata(process)); misses += 1
            }
            if process.identity > 0 { next[key] = entry }
            result[process.pid] = entry.value
        }
        entries = next // Departed processes cannot accumulate indefinitely.
        return result
    }
}
struct ProcessMetadata {
    struct App { let path: String; let title: String; let details: ProcessDescription }
    let title: String
    let category: String
    let executableKey: String
    let details: ProcessDescription
    let aiName: String?
    let aiWhat: String?
    let bundle: App?
    init(_ p: ProcessSample) {
        title = ProcessIdentity.safeTitle(p.name, path: p.path, pid: p.pid)
        category = p.path.isEmpty ? "Unknown" : p.path.hasPrefix("/System/") || p.path.hasPrefix("/usr/libexec/") ? "System" : "Command-line"
        executableKey = p.path.isEmpty ? "pid:\(p.pid):\(p.identity):\(ProcessIdentity.executable(p))" : "exec:\(ProcessIdentity.canonical(p.path))"
        details = ProcessDictionary.details(name: title, path: p.path)
        aiName = AgentKind.name(processName: p.name, path: p.path)
        aiWhat = aiName.map { ProcessDictionary.details(name: $0).what }
        if let path = ProcessIdentity.bundlePath(p.path) {
            let fallback = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let display = Bundle(path: path)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? fallback
            let name = ProcessIdentity.safeTitle(display, path: path, pid: p.pid)
            bundle = App(path: path, title: name, details: ProcessDictionary.details(name: name, path: p.path))
        } else { bundle = nil }
    }
}

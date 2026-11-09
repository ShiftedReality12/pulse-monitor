import Foundation
import Darwin

public enum Attribution {
    public static func groups(_ processes: [ProcessSample]) -> [ProcessGroup] {
        var metadata = ProcessMetadataCache()
        return groups(processes, metadata: &metadata)
    }
    static func groups(_ processes: [ProcessSample], metadata: inout ProcessMetadataCache) -> [ProcessGroup] {
        let resolved = metadata.prepare(processes)
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        struct Owner {
            var id: String; var title: String; var category: String
            var launcher: String?; var cwd: String?; var description: String; var why: String; var limited: Bool
            var configHome: String? = nil; var pane: String? = nil
        }
        func aiName(_ p: ProcessSample) -> String? { resolved[p.pid]?.aiName }
        func owner(_ process: ProcessSample) -> Owner {
            let ancestry = ProcessIdentity.chain(process, byPID: byPID), chain = ancestry.members
            if let root = chain.last(where: { aiName($0) != nil }), let title = aiName(root) {
                let cwd = root.cwd
                let ancestors = chain.drop(while: { $0.pid != root.pid }).dropFirst()
                let launcher = ancestors.first(where: { [HerdrProvider.processName, "Terminal", "iTerm2", "Code", "Cursor", "sshd"].contains($0.name) })?.name
                    ?? ancestors.compactMap { ProcessIdentity.bundlePath($0.path).map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } }.first
                let project = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                let why = "Started by \(launcher ?? "an unverified launcher") in \(cwd.map(shortPath) ?? "an unavailable folder")."
                let key = "ai:\(root.pid):\(root.identity)" + (root.identity == 0 ? ":\(ProcessIdentity.executable(root))" : "")
                return Owner(id: key, title: title + (project.map { " · \($0)" } ?? ""), category: "AI session", launcher: launcher, cwd: cwd, description: resolved[root.pid]?.aiWhat ?? "AI coding session.", why: why, limited: ancestry.limited, configHome: root.configDir.map(shortPath) ?? (root.agentEnvironmentRead ? AgentKind.defaultHome(for: title) : nil), pane: root.pane)
            }
            if let info = adoptedApp(process, resolved: resolved, byPID: byPID) {
                return Owner(id: "app:\(info.path)", title: info.title, category: "App", launcher: "launchd", cwd: process.cwd, description: info.details.what, why: "Helper started by launchd or XPC for \(info.title).", limited: ancestry.limited)
            }
            if let app = chain.first(where: { resolved[$0.pid]?.bundle != nil }), let info = resolved[app.pid]?.bundle {
                let bundle = info.path, name = info.title
                let appIndex = chain.firstIndex(where: { $0.pid == app.pid }) ?? 0
                let parents = chain.dropFirst(appIndex + 1)
                let why = bundle == "/Applications/Grok Bot.app" ? info.details.why : parents.contains(where: { $0.name == "loginwindow" }) ? "Login item or login-session app, started by loginwindow." : parents.contains(where: { $0.name == "launchd" }) ? "Started by launchd; the exact trigger (on demand or login item) is unavailable." : "Launch reason unavailable; macOS did not expose a verified launcher."
                return Owner(id: "app:\(bundle)", title: name, category: "App", launcher: parents.first?.name, cwd: process.cwd, description: info.details.what, why: why, limited: ancestry.limited)
            }
            let info = resolved[process.pid]!
            let why = chain.dropFirst().first.map { "Started by \($0.name). \(info.details.why)" } ?? info.details.why
            return Owner(id: info.executableKey, title: info.title, category: info.category, launcher: chain.dropFirst().first?.name, cwd: process.cwd, description: info.details.what, why: why, limited: ancestry.limited)
        }
        let owners = processes.map { ($0, owner($0)) }
        return Dictionary(grouping: owners, by: { $0.1.id }).map { id, items in
            let value = items[0].1, members = items.map(\.0)
            let caller = Int32(getuid())
            let missing = members.filter { $0.resident == nil }
            var group = ProcessGroup(id: id, title: value.title, members: members.map(\.pid).sorted(), resident: sum(members.compactMap(\.resident)), cpu: sum(members.compactMap(\.cpu)), limited: items.contains { $0.1.limited || $0.0.resident == nil || $0.0.cpu == nil || $0.0.writesPerSecond == nil })
            group.rss = sum(members.compactMap(\.rss))
            group.needsAdmin = group.resident == nil && !missing.isEmpty && missing.allSatisfy { $0.uid >= 0 && $0.uid != caller }
            group.configHome = value.configHome; group.pane = value.pane; group.category = value.category; group.explanation = value.description; group.launcher = value.launcher; group.cwd = value.cwd; group.runningReason = value.why
            group.aiProcessCount = members.filter { aiName($0) != nil }.count
            group.writesPerSecond = sum(members.compactMap(\.writesPerSecond))
            group.hasVerifiedIdentity = members.allSatisfy { $0.identity > 0 }
            group.startedAt = members.map(\.identity).filter { $0 > 0 }.min().map { Date(timeIntervalSince1970: Double($0) / 1e6) }
            return group
        }
    }
    /// A launchd/XPC helper has no app in its parent chain. Follow the responsible pid to the owning app.
    private static func adoptedApp(_ process: ProcessSample, resolved: [Int32: ProcessMetadata], byPID: [Int32: ProcessSample]) -> ProcessMetadata.App? {
        guard process.responsible > 0, resolved[process.pid]?.bundle == nil, let host = byPID[process.responsible] else { return nil }
        let hostChain = ProcessIdentity.chain(host, byPID: byPID).members
        return hostChain.compactMap { resolved[$0.pid]?.bundle }.first
    }
    private static func sum<T: AdditiveArithmetic>(_ values: [T]) -> T? { values.isEmpty ? nil : values.reduce(.zero, +) }
    private static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

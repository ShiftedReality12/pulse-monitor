import Foundation

/// Generic sample labels for `PULSE_DEMO=1` screenshots. Never used when the flag is unset.
public enum DemoData {
    private static let projects = ["project-a", "project-b", "project-c"]
    private static let accounts = ["~/Account A", "~/Account B", "~/Account C"]
    private static let panes = ["demo-pane-1", "demo-pane-2", "demo-pane-3"]

    /// SwiftBar-shaped usage text with only generic account names.
    public static let usageSwiftBar = """
    ◔ 42% · wk 55% | color=#28858B
    ---
    Account A | color=#A65D20 font=Menlo size=13
    5h  ███░░░░░░░  30% used · 70% left · resets in 3h 12m | font=Menlo size=12 refresh=true
    7d  █████░░░░░  55% used · 45% left · resets in 2d 4h | font=Menlo size=12 refresh=true
    updated 1m ago | color=#888888 size=11
    ---
    Account B | color=#9264B0 font=Menlo size=13
    5h  ██████░░░░  62% used · 38% left · resets in 1h 5m | font=Menlo size=12 refresh=true
    updated 1m ago | color=#888888 size=11
    ---
    Refresh | refresh=true
    """

    /// Rewrites AI session labels to generic demo values and injects sample sessions when none are live.
    public static func anonymizeGroups(_ groups: [ProcessGroup]) -> [ProcessGroup] {
        var aiIndex = 0
        var result = groups.map { group -> ProcessGroup in
            guard group.category == "AI session" else { return group }
            let index = aiIndex
            aiIndex += 1
            return labeled(group, index: index)
        }
        let existing = result.filter { $0.category == "AI session" }.count
        if existing < 2 {
            for index in existing..<2 {
                result.append(syntheticSession(index: index))
            }
        }
        return result
    }

    private static func labeled(_ group: ProcessGroup, index: Int) -> ProcessGroup {
        let project = projects[index % projects.count]
        let agent = group.title.split(separator: " · ").first.map(String.init).flatMap { $0.isEmpty ? nil : $0 } ?? "Claude Code"
        var next = group
        next.title = "\(agent) · \(project)"
        next.cwd = "/home/demo/\(project)"
        next.configHome = accounts[index % accounts.count]
        next.pane = panes[index % panes.count]
        next.launcher = next.launcher ?? "herdr"
        next.runningReason = "Started by \(next.launcher ?? "herdr") in /home/demo/\(project)."
        if next.explanation.isEmpty { next.explanation = "AI coding session." }
        return next
    }

    private static func syntheticSession(index: Int) -> ProcessGroup {
        let project = projects[index % projects.count]
        let agent = index == 0 ? "Claude Code" : "Codex"
        var group = ProcessGroup(
            id: "demo:ai:\(index)",
            title: "\(agent) · \(project)",
            members: [Int32(90_000 + index)],
            resident: UInt64((3 - index) * 450_000_000),
            cpu: Double(2.5 - Double(index) * 0.7),
            limited: false
        )
        group.category = "AI session"
        group.explanation = "AI coding session."
        group.cwd = "/home/demo/\(project)"
        group.configHome = accounts[index % accounts.count]
        group.pane = panes[index % panes.count]
        group.launcher = "herdr"
        group.runningReason = "Started by herdr in /home/demo/\(project)."
        group.memoryTrend = [0.18, 0.22, 0.25, 0.24, 0.28, 0.3]
        group.aiProcessCount = 1
        group.hasVerifiedIdentity = true
        group.startedAt = Date().addingTimeInterval(-1_800 * Double(index + 1))
        return group
    }
}

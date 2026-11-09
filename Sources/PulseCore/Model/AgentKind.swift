import Foundation

/// The one place that decides whether a process is an AI agent CLI.
enum AgentKind {
    static func name(processName: String, path: String) -> String? {
        let name = processName.lowercased(), executable = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if name == "codex" || executable == "codex" { return "Codex" }
        if name == "claude" || executable == "claude" || name == "claude code" || path.contains("/claude/versions/") { return "Claude Code" }
        return nil
    }
    /// Where an agent keeps its state when no configuration variable redirects it.
    static func defaultHome(for agent: String) -> String { agent == "Codex" ? "~/.codex" : "~/.claude" }
}

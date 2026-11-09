import Foundation

/// Parsed, display-only view of an optional usage reader's SwiftBar text. Nothing here is stored or sent anywhere.
public struct UsageWindow: Sendable, Equatable {
    public var label: String
    public var usedPercent: Int
    public var leftPercent: Int
    public var resets: String
}
public struct UsageAccount: Sendable, Equatable, Identifiable {
    public var name: String
    public var windows: [UsageWindow] = []
    public var notes: [String] = []
    public var updated: String?
    public var problem: String?
    public var id: String { name }
    public var worstUsed: Int { windows.map(\.usedPercent).max() ?? 0 }
    public enum Status: String, Sendable { case ok = "OK", watch = "Getting full", limit = "Limit reached", unavailable = "Unavailable" }
    public var status: Status {
        if windows.isEmpty { return .unavailable }
        return worstUsed >= 100 ? .limit : worstUsed >= 80 ? .watch : .ok
    }
}
public enum UsageReport {
    public static func parse(_ text: String) -> [UsageAccount] {
        var blocks: [[String]] = [[]]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "---" { blocks.append([]) } else { blocks[blocks.count - 1].append(line) }
        }
        return blocks.dropFirst().compactMap(account)
    }
    private static func visible(_ line: String) -> String {
        (line.range(of: " | ").map { String(line[..<$0.lowerBound]) } ?? line).trimmingCharacters(in: .whitespaces)
    }
    private static func account(_ block: [String]) -> UsageAccount? {
        let lines = block.filter { !$0.isEmpty }
        guard let title = lines.first.map(visible), !title.isEmpty, title != "Refresh" else { return nil }
        var account = UsageAccount(name: title)
        for raw in lines.dropFirst() {
            if raw.contains("href=") { continue } // never surface or follow links
            let line = visible(raw)
            if let window = window(line) { account.windows.append(window) }
            else if line.hasPrefix("updated ") { account.updated = String(line.dropFirst(8)) }
            else if line.hasPrefix("credits ") { account.notes.append(line) }
            else if !line.isEmpty { account.problem = account.problem ?? line }
        }
        return account.windows.isEmpty && account.problem == nil ? nil : account
    }
    private static func window(_ line: String) -> UsageWindow? {
        guard let match = line.firstMatch(of: /^(\S+)\s+[█░▒▓ ]+\s+(\d+)% used · (\d+)% left · resets in (.+)$/),
              let used = Int(match.2), let left = Int(match.3) else { return nil }
        return UsageWindow(label: String(match.1), usedPercent: used, leftPercent: left, resets: String(match.4))
    }
}
extension UsageWindow {
    public var labelName: String {
        switch label { case "5h": "5-hour"; case "7d": "7-day"; case "wk": "Weekly"; default: label }
    }
}

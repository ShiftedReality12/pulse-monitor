import Foundation
import Darwin

public struct HerdrProvider: PulseProvider {
    public static let processName = "herdr"
    public let id = "herdr"
    public let cadence = 30.0
    public var section: String? { "Sessions" }
    private let path: String
    /// A Finder or launchd launch has a minimal PATH, so common install folders are also searched.
    private let fallbacks: [String]
    public init(path: String = PulseEnvironment.providerPath(), fallbacks: [String]? = nil) {
        self.path = path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.fallbacks = fallbacks ?? (PulseEnvironment.providerPathOverridden() ? [] : ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.cargo/bin"])
    }
    public func isAvailable() -> Bool {
        (path.split(separator: ":").map(String.init) + fallbacks).contains { access($0 + "/" + Self.processName, X_OK) == 0 }
    }
    /// Input contract for a future read-only pane snapshot adapter; no terminal content is read.
    public func panes(processes: [ProcessSample], paneByPID: [Int32: String]) -> [Int32: String] {
        Dictionary(uniqueKeysWithValues: processes.compactMap { process in paneByPID[process.pid].map { (process.pid, $0) } })
    }
}
public struct AgentAccountsProvider: PulseProvider {
    public let id = "agent-accounts"
    public let cadence = 60.0
    public var section: String? { "Sessions" }
    private let home: URL
    public init(home: URL = PulseEnvironment.providerHome()) { self.home = home }
    public func isAvailable() -> Bool {
        [".claude", ".codex"].contains { FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path) }
    }
    /// Accept only the two configuration-home variables from a caller-supplied process environment.
    /// Acquiring per-process environments and rendering accounts are deferred to v7.
    public func accountHome(environment: [String: String], cwd: String?) -> URL? {
        guard let path = environment["CLAUDE_CONFIG_DIR"] ?? environment["CODEX_HOME"], !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
        guard let cwd, cwd.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: cwd).appendingPathComponent(path).standardizedFileURL
    }
}
public struct UsageStripProvider: PulseProvider {
    public let id = "usage-strip"
    public let cadence = 60.0
    public var section: String? { "Usage" }
    private let executable: URL
    /// `home` selects `<home>/bin/usage`. Omit it to honour `PULSE_USAGE_EXECUTABLE` / provider-home defaults.
    public init(home: URL? = nil) {
        if let home {
            executable = home.appendingPathComponent("bin/usage")
        } else {
            executable = PulseEnvironment.usageExecutable()
        }
    }
    public init(executable: URL) { self.executable = executable }
    public func isAvailable() -> Bool { access(executable.path, X_OK) == 0 }
    /// Explicit, bounded read (at most the given seconds); never persisted.
    public func sample(timeout: Double = 1) async -> String? {
        guard isAvailable() else { return nil }
        let executable = executable
        return await Task.detached(priority: .utility) { ProviderCommand.read(executable: executable, arguments: ["--swiftbar"], timeout: timeout) }.value
    }
    public func report(timeout: Double = 8) async -> [UsageAccount]? {
        await sample(timeout: timeout).map(UsageReport.parse)
    }
}

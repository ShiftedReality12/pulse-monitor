import Foundation
import Testing
import CSensors
@testable import PulseCore

private let sampleUsage = """
◔ 100% · wk 70% | color=#C74040
---
Claude main | color=#A65D20 font=Menlo size=13
5h  █░░░░░░░░░  1% used · 99% left · resets in 4h 34m | font=Menlo size=12 refresh=true
7d  ███████░░░  70% used · 30% left · resets in 24h 44m | font=Menlo size=12 refresh=true
updated 8m ago | color=#888888 size=11
---
Claude team@ | color=#9264B0 font=Menlo size=13
5h  ██████████  100% used · 0% left · resets in 14m | font=Menlo size=12 refresh=true color=#C74040
updated 0m ago | color=#888888 size=11
---
Codex | color=#28858B font=Menlo size=13
wk  █████████░  85% used · 15% left · resets in 5d 5h | font=Menlo size=12 refresh=true color=#C74040
credits 62,497 | color=#888888 size=11
updated 180m ago | color=#888888 size=11
---
Grok | color=#82752D font=Menlo size=13
HTTPError 401 | color=#888888 font=Menlo size=12
updated 0m ago | color=#888888 size=11
Open grok.com | href=https://example.invalid
---
Refresh | refresh=true
"""
@Test func usageReportParsesAccountsWindowsStatusAndProblems() {
    let accounts = UsageReport.parse(sampleUsage)
    #expect(accounts.map(\.name) == ["Claude main", "Claude team@", "Codex", "Grok"])
    #expect(accounts[0].windows.map(\.label) == ["5h", "7d"])
    #expect(accounts[0].windows[1].usedPercent == 70 && accounts[0].windows[1].leftPercent == 30 && accounts[0].windows[1].resets == "24h 44m")
    #expect(accounts[0].updated == "8m ago" && accounts[0].status == .ok)
    #expect(accounts[1].status == .limit && accounts[1].worstUsed == 100)
    #expect(accounts[2].status == .watch && accounts[2].notes == ["credits 62,497"] && accounts[2].windows[0].labelName == "Weekly")
    #expect(accounts[3].status == .unavailable && accounts[3].problem == "HTTPError 401" && accounts[3].windows.isEmpty)
}
@Test func usageReportNeverSurfacesLinksAndToleratesGarbage() {
    #expect(UsageReport.parse(sampleUsage).allSatisfy { !($0.problem ?? "").contains("Open grok") })
    #expect(UsageReport.parse("").isEmpty)
    #expect(UsageReport.parse("not a swiftbar document").isEmpty)
    #expect(UsageReport.parse("title\n---\nRefresh | refresh=true").isEmpty)
    #expect(UsageReport.parse("x\n---\nA\n5h  ██  200% used · 0% left · resets in 1m").first?.status == .limit)
}
@Test func providerDetectionFollowsEnvironmentOverridesWithoutTouchingFiles() throws {
    let missing = ["PULSE_PROVIDER_HOME": "/nonexistent-pulse-provider-home", "PULSE_PROVIDER_PATH": "/nonexistent-pulse-path"]
    #expect(PulseEnvironment.providerHome(missing).path == "/nonexistent-pulse-provider-home")
    #expect(PulseEnvironment.providerPath(missing) == "/nonexistent-pulse-path")
    #expect(PulseEnvironment.providerHome(["PULSE_PROVIDER_HOME": "relative"]) == FileManager.default.homeDirectoryForCurrentUser)
    var registry = ProviderRegistry(providers: [HerdrProvider(path: PulseEnvironment.providerPath(missing), fallbacks: []),
                                                AgentAccountsProvider(home: PulseEnvironment.providerHome(missing)),
                                                UsageStripProvider(home: PulseEnvironment.providerHome(missing))])
    registry.refresh(at: 0)
    #expect(registry.available.isEmpty && registry.sections.isEmpty)
}
@Test func usageProviderReportParsesTheExplicitReaderAndSectionsAppearOnlyWhenDetected() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-v7-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let bin = home.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    #expect(await UsageStripProvider(home: home).report() == nil)
    let executable = bin.appendingPathComponent("usage")
    try Data("#!/bin/sh\ncat <<'EOF'\ntitle\n---\nAcct\n5h  █░  10% used · 90% left · resets in 1h\nupdated 0m ago\nEOF\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let accounts = await UsageStripProvider(home: home).report()
    #expect(accounts?.first?.name == "Acct" && accounts?.first?.windows.first?.usedPercent == 10)
    #expect(UsageStripProvider(home: home).section == "Usage")
}
/// macOS hides the environment of Apple platform binaries, so the child is a tiny locally compiled program.
@Test func agentContextComesOnlyFromWhitelistedEnvironmentVariables() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-env-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("sleeper.c"), binary = directory.appendingPathComponent("sleeper")
    try Data("#include <unistd.h>\nint main(void){ sleep(20); return 0; }\n".utf8).write(to: source)
    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang"); compiler.arguments = [source.path, "-o", binary.path]
    try compiler.run(); compiler.waitUntilExit()
    #expect(compiler.terminationStatus == 0)
    let process = Process()
    process.executableURL = binary
    process.environment = ["CLAUDE_CONFIG_DIR": "/tmp/pulse-demo-acct", "HERDR_PANE_ID": "demo-pane-9", "UNRELATED_SECRET": "not-a-real-secret"]
    try process.run()
    defer { process.terminate(); process.waitUntilExit() }
    func read(_ key: String) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        return pulse_process_env(process.processIdentifier, key, &buffer, 256) == 1 ? String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
    }
    for _ in 0..<300 where read("CLAUDE_CONFIG_DIR") == nil { Thread.sleep(forTimeInterval: 0.01) } // wait for exec to install the child's environment
    #expect(read("CLAUDE_CONFIG_DIR") == "/tmp/pulse-demo-acct")
    #expect(read("HERDR_PANE_ID") == "demo-pane-9")
    #expect(read("CODEX_HOME") == nil)
    #expect(read("CLAUDE_CONFIG") == nil) // a prefix of a name never matches
    #expect(read("RESET_SECRET") == nil && read("") == nil)
    var small = [CChar](repeating: 0, count: 5)
    #expect(pulse_process_env(process.processIdentifier, "CLAUDE_CONFIG_DIR", &small, 5) == 1 && String(decoding: small.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) == "/tmp") // truncated, never overflowed
}
@Test func agentGroupsCarryAccountFolderAndPaneFromTheirRootProcess() {
    var root = ProcessSample(pid: 10, identity: 100, name: "claude", path: "/opt/tools/claude/versions/9/claude", resident: 300_000_000, cpu: 4)
    root.configDir = "/home/example/.claude-demo9"; root.pane = "demo-pane-3"; root.cwd = "/home/example/demo/project"
    var child = ProcessSample(pid: 11, identity: 101, name: "node", path: "/usr/local/bin/node", resident: 100_000_000, cpu: 1)
    child.parent = 10
    var plain = ProcessSample(pid: 12, identity: 102, name: "codex", path: "/opt/tools/codex", resident: 50_000_000, cpu: 0.5)
    plain.cwd = "/home/example/demo/other"; plain.agentEnvironmentRead = true
    let groups = Attribution.groups([root, child, plain])
    let claude = groups.first { $0.title.hasPrefix("Claude Code") }
    #expect(claude?.members == [10, 11] && claude?.resident == 400_000_000 && claude?.cpu == 5)
    #expect(claude?.pane == "demo-pane-3" && claude?.configHome?.hasSuffix("/.claude-demo9") == true)
    let codex = groups.first { $0.title.hasPrefix("Codex") }
    #expect(codex?.configHome == "~/.codex" && codex?.pane == nil)
    #expect(groups.filter { $0.category == "AI session" }.count == 2)
}
@Test func agentKindRecognizesOnlyAgentCLIs() {
    #expect(AgentKind.name(processName: "claude", path: "/x/claude") == "Claude Code")
    #expect(AgentKind.name(processName: "2.1.9", path: "/home/u/.local/share/claude/versions/2.1.9") == "Claude Code")
    #expect(AgentKind.name(processName: "codex", path: "") == "Codex")
    #expect(AgentKind.name(processName: "node", path: "/usr/bin/node") == nil)
}
@Test func anUnreadableEnvironmentIsUnknownNotTheDefaultAccount() {
    var unreadable = ProcessSample(pid: 20, identity: 200, name: "claude", path: "/opt/tools/claude/versions/9/claude", resident: 1, cpu: 0)
    unreadable.agentEnvironmentRead = false
    var readable = ProcessSample(pid: 21, identity: 201, name: "claude", path: "/opt/tools/claude/versions/9/claude", resident: 1, cpu: 0)
    readable.agentEnvironmentRead = true
    let groups = Attribution.groups([unreadable, readable])
    #expect(groups.first { $0.members == [20] }?.configHome == nil)
    #expect(groups.first { $0.members == [21] }?.configHome == "~/.claude")
}
@Test func environmentReadDistinguishesAbsentFromUnreadable() {
    var buffer = [CChar](repeating: 0, count: 64)
    #expect(pulse_process_env(2_000_000_000, "CLAUDE_CONFIG_DIR", &buffer, 64) == -1) // no such process
    #expect(pulse_process_env(getpid(), "PULSE_SURELY_ABSENT_VARIABLE", &buffer, 64) <= 0)
}
@Test func herdrIsFoundInStandardFoldersEvenWithAMinimalPathButNotWhenOverridden() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-herdr-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let tool = folder.appendingPathComponent(HerdrProvider.processName)
    try Data("#!/bin/sh\n".utf8).write(to: tool)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
    #expect(HerdrProvider(path: "/usr/bin", fallbacks: [folder.path]).isAvailable())
    #expect(!HerdrProvider(path: "/usr/bin", fallbacks: []).isAvailable())
    #expect(HerdrProvider(path: folder.path, fallbacks: []).isAvailable())
}

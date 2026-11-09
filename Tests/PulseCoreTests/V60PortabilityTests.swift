import Foundation
import Testing
@testable import PulseCore

@Test func sourcesContainNoPersonalPathsOrNames() throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let files = FileManager.default.enumerator(at: repo.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)!
    for case let file as URL in files where ["swift", "c", "h"].contains(file.pathExtension) {
        let source = try String(contentsOf: file, encoding: .utf8)
        let homePrefix = "/" + "Users/"
        // Personal tokens are assembled so this test file itself stays scrub-clean.
        let personal = ["dani", "elsardina"].joined()
        let brand = ["tal", "yx"].joined()
        for forbidden in [homePrefix, personal, brand] { #expect(!source.localizedCaseInsensitiveContains(forbidden), "\(file.lastPathComponent): \(forbidden)") }
    }
}
@Test func portableRootsDiscoverExistingFoldersAndGateConfiguredProtectedRoots() async throws {
    let home = try disk59Fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    for name in ["workspaces", ".codex", "Music", "extra"] { try disk59File(home.appendingPathComponent(name + "/data")) }
    let config = home.appendingPathComponent("Library/Application Support/Pulse/config.json")
    try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{\"extraRoots\":[\"~/extra\",\"~/Music\",\"relative/ignored\"]}".utf8).write(to: config)
    let service = DiskEstimates(home: home, probe: { false }, cacheURL: nil)
    let result = await service.load()
    #expect(result.first { $0.path == home.appendingPathComponent("workspaces").path }?.bytes == 4096)
    #expect(result.first { $0.path == home.appendingPathComponent("extra").path }?.bytes == 4096)
    #expect(result.first { $0.path == home.appendingPathComponent("Music").path }?.bytes == nil)
    #expect(!DiskRootPlan.defaults(home: home).contains { $0.path == home.appendingPathComponent(".claude").path })
}
private struct CountingProvider: PulseProvider {
    let id: String
    let available: Bool
    var cadence: Double { 60 }
    var section: String? { available ? id : nil }
    func isAvailable() -> Bool { available }
}
@Test func providerRegistryHidesAbsentIntegrationsAndRechecksSlowly() {
    var registry = ProviderRegistry(providers: [CountingProvider(id: "yes", available: true), CountingProvider(id: "no", available: false)])
    registry.refresh(at: 0)
    #expect(registry.available.map(\.id) == ["yes"])
    #expect(registry.sections == ["yes"])
    #expect(registry.detections == 1)
    for index in 1..<900 { registry.refresh(at: Double(index)) }
    #expect(registry.detections == 1)
    registry.refresh(at: 900)
    #expect(registry.detections == 2)
}
@Test func optionalProviderAdaptersUseOnlyExplicitInputsAndBoundCommandOutput() async throws {
    let home = try disk59Fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    let accounts = AgentAccountsProvider(home: home)
    #expect(!accounts.isAvailable())
    #expect(accounts.accountHome(environment: ["CLAUDE_CONFIG_DIR": "config"], cwd: home.path)?.path == home.appendingPathComponent("config").path)
    #expect(accounts.accountHome(environment: ["UNRELATED": "ignored"], cwd: home.path) == nil)
    let absent = UsageStripProvider(home: home)
    #expect(!absent.isAvailable())
    #expect(await absent.sample() == nil)
    let executable = home.appendingPathComponent("bin/usage")
    try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\nprintf '42%% remaining\\n'\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    // Cold spawn of a new fixture can take ~0.8s on some hosts; keep production default at 1s.
    #expect(await UsageStripProvider(home: home).sample(timeout: 5) == "42% remaining\n")
    #expect(ProviderCommand.read(executable: executable, arguments: [], limit: 2) == nil)
    try Data("#!/bin/sh\nexec /bin/sleep 5\n".utf8).write(to: executable)
    let started = ProcessInfo.processInfo.systemUptime
    #expect(ProviderCommand.read(executable: executable, arguments: [], timeout: 0.05) == nil)
    #expect(ProcessInfo.processInfo.systemUptime - started < 1)
}
@Test func trashIsOmittedBeforeMetadataEvenWhenExplicitlyConfigured() async throws {
    let home = try disk59Fixture()
    defer { try? FileManager.default.removeItem(at: home) }
    try disk59File(home.appendingPathComponent(".Trash/data"))
    let forbidden = home.appendingPathComponent(".Trash").path
    let service = DiskEstimates(home: home, probe: { false }, observer: { path in
        #expect(path != forbidden && !path.hasPrefix(forbidden + "/"))
    }, cacheURL: nil)
    #expect(await service.load().allSatisfy { $0.path != forbidden })
    #expect(await service.load(roots: [URL(fileURLWithPath: forbidden)]).isEmpty)
    #expect(await service.load(roots: [URL(fileURLWithPath: forbidden.lowercased() + "/child")]).isEmpty)
    _ = await service.load(roots: [home])
}

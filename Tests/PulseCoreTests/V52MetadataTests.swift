import Foundation
import Testing
import CSensors
@testable import PulseCore

private func metadataProcess(_ pid: Int32, start: UInt64 = 100, name: String = "tool", path: String = "/bin/tool", parent: Int32 = 0) -> ProcessSample {
    var p = ProcessSample(pid: pid, identity: start, name: name, path: path, resident: 40, cpu: 3)
    p.parent = parent; p.writesPerSecond = 0; return p
}
@Test func metadataCacheInvalidatesIdentityPathAndNameAndPrunes() {
    var cache = ProcessMetadataCache()
    let first = metadataProcess(20, name: "codex", path: "/bin/codex")
    #expect(cache.prepare([first])[20]?.aiName == "Codex")
    #expect(cache.misses == 1)
    _ = cache.prepare([first]); #expect(cache.hits == 1 && cache.misses == 1)
    _ = cache.prepare([metadataProcess(20, start: 200, name: "codex", path: "/bin/codex")])
    #expect(cache.misses == 2)
    let moved = metadataProcess(20, start: 200, name: "tool", path: "/other/tool")
    #expect(cache.prepare([moved])[20]?.aiName == nil)
    #expect(cache.misses == 3 && cache.count == 1)
    #expect(cache.prepare([metadataProcess(20, start: 200, name: "claude", path: "/other/tool")])[20]?.aiName == "Claude Code")
    #expect(cache.misses == 4)
    _ = cache.prepare([]); #expect(cache.count == 0)
    _ = cache.prepare([first]); #expect(cache.misses == 5)
}
@Test func metadataCacheNeverReusesUnknownProcessIdentity() {
    var cache = ProcessMetadataCache()
    let p = metadataProcess(20, start: 0)
    _ = cache.prepare([p]); _ = cache.prepare([p])
    #expect(cache.hits == 0 && cache.misses == 2 && cache.count == 0)
}
@Test func cachedClassificationStillUsesNewParentAndCwd() {
    var cache = ProcessMetadataCache()
    var a = metadataProcess(10, start: 10, name: "codex", path: "/bin/codex")
    var b = metadataProcess(40, start: 40, name: "claude", path: "/bin/claude")
    var child = metadataProcess(50, start: 50, name: "git", path: "/bin/git", parent: 10)
    a.cwd = "/work/a"; b.cwd = "/work/b"
    let first = Attribution.groups([a, b, child], metadata: &cache)
    #expect(first.first { $0.id == "ai:10:10" }?.members == [10, 50])
    child.parent = 40; b.cwd = "/work/new-folder"
    let second = Attribution.groups([a, b, child], metadata: &cache)
    #expect(cache.hits == 3)
    #expect(second.first { $0.id == "ai:10:10" }?.members == [10])
    #expect(second.first { $0.id == "ai:40:40" }?.members == [40, 50])
    #expect(second.first { $0.id == "ai:40:40" }?.runningReason.contains("/work/new-folder") == true)
}
@Test func processSamplerActuallyReusesClassificationAcrossRefreshes() {
    let sampler = ProcessSampler(bridge: { output, _, _, _ in
        guard let output else { return 1 }
        var p = PulseProcess(); p.pid = 52; p.started = 100; p.readable = 1
        withUnsafeMutableBytes(of: &p.name) { $0.copyBytes(from: Array("codex\0".utf8)) }
        withUnsafeMutableBytes(of: &p.path) { $0.copyBytes(from: Array("/bin/codex\0".utf8)) }
        output.pointee = p; return 1
    })
    var s = Snapshot(); sampler.collect(into: &s, now: 0); sampler.collect(into: &s, now: 6)
    #expect(sampler.metadataStats.hits == 1 && sampler.metadataStats.misses == 1)
    #expect(s.groups.first?.title == "Codex")
}
@Test func processCollectionStaysAtSixSecondsWhileVitalsTickAtTwo() {
    var calls = 0
    let sampler = Sampler(processes: ProcessSampler(bridge: { _, _, _, _ in calls += 1; return 0 }))
    for time in [0.0, 2, 4] { _ = sampler.sample(includeProcesses: true, uptime: time) }
    #expect(calls == 2)
    _ = sampler.sample(includeProcesses: true, uptime: 6); #expect(calls == 4)
    _ = sampler.sample(includeProcesses: true, uptime: 8); #expect(calls == 4)
    #expect(SamplingPolicy.interval(visible: true) == 2)
    #expect(SamplingPolicy.processInterval(visible: true) >= 4)
}

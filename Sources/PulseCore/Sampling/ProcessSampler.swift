import Foundation
import CSensors

final class ProcessSampler {
    typealias Bridge = (UnsafeMutablePointer<PulseProcess>?, Int32, UnsafeMutablePointer<Int32>?, Int32) -> Int32
    private let bridge: Bridge
    private var metadata = ProcessMetadataCache()
    var metadataStats: (hits: Int, misses: Int, entries: Int) { (metadata.hits, metadata.misses, metadata.count) }
    init(bridge: @escaping Bridge = { pulse_processes($0, $1, $2, $3) }, readsAgentContext: Bool? = nil) {
        self.bridge = bridge
        self.readsAgentContext = readsAgentContext ?? (AgentAccountsProvider().isAvailable() || HerdrProvider().isAvailable())
    }
    func reset() { previousProcesses.removeAll(keepingCapacity: true); previousProcessTime = nil; agentContext.removeAll() }
    private var previousProcesses: [Int32: (identity: UInt64, cpu: UInt64, writes: UInt64?)] = [:]
    private var previousProcessTime: TimeInterval?
    private var agentContext: [Int32: (identity: UInt64, configDir: String?, pane: String?)] = [:]
    /// Environments are read only when an agent-related integration was detected; otherwise nothing could be shown anyway.
    private let readsAgentContext: Bool
    private func context(for p: PulseProcess, name: String, path: String, cwd: String?) -> (configDir: String?, pane: String?, read: Bool)? {
        guard readsAgentContext, p.started > 0, AgentKind.name(processName: name, path: path) != nil else { return nil }
        if let cached = agentContext[p.pid], cached.identity == p.started { return (cached.configDir, cached.pane, true) }
        var readable = true
        func read(_ key: String) -> String? {
            var buffer = [CChar](repeating: 0, count: 1024)
            let status = pulse_process_env(p.pid, key, &buffer, Int32(buffer.count))
            if status < 0 { readable = false }
            return status == 1 ? String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
        }
        var environment: [String: String] = [:]
        for key in ["CLAUDE_CONFIG_DIR", "CODEX_HOME"] { if let value = read(key) { environment[key] = value } }
        let configDir = AgentAccountsProvider().accountHome(environment: environment, cwd: cwd)?.path
        let pane = read("HERDR_PANE_ID")
        guard readable else { return (nil, nil, false) } // unreadable: unknown, and retried at the next refresh
        agentContext[p.pid] = (p.started, configDir, pane)
        return (configDir, pane, true)
    }
    private var processBuffer: UnsafeMutableBufferPointer<PulseProcess> = .allocate(capacity: 0)
    private var pidBuffer: UnsafeMutableBufferPointer<Int32> = .allocate(capacity: 0)
    deinit { processBuffer.deallocate(); pidBuffer.deallocate() }
    func collect(into s: inout Snapshot, now: TimeInterval) {
        // Count and allocate only at process refresh; reuse both C buffers thereafter.
        let needed = max(64, Int(bridge(nil, 0, nil, 0)))
        if processBuffer.count < needed {
            processBuffer.deallocate(); pidBuffer.deallocate()
            processBuffer = .allocate(capacity: needed + 128)
            pidBuffer = .allocate(capacity: needed + 128)
        }
        let count = Int(bridge(processBuffer.baseAddress, Int32(processBuffer.count), pidBuffer.baseAddress, Int32(pidBuffer.count)))
        let elapsed = previousProcessTime.map { now - $0 }
        var current: [Int32: (identity: UInt64, cpu: UInt64, writes: UInt64?)] = [:]
        current.reserveCapacity(count)
        let samples = (0..<count).map { index -> ProcessSample in
            let p = processBuffer[index]
            let name = withUnsafeBytes(of: &processBuffer[index].name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let path = withUnsafeBytes(of: &processBuffer[index].path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            var cpu: Double?
            if p.readable != 0 && p.started > 0 {
                current[p.pid] = (p.started, p.cpu_ns, p.io_ok != 0 ? p.disk_written : nil)
                if let old = previousProcesses[p.pid], old.identity == p.started, p.started > 0, let elapsed, elapsed > 0, p.cpu_ns >= old.cpu {
                    cpu = Double(p.cpu_ns - old.cpu) / (elapsed * 1e9) * 100
                }
            }
            let rss = p.readable != 0 ? p.resident : nil
            let footprint = p.footprint > 0 ? p.footprint : nil
            var sample = ProcessSample(pid: p.pid, identity: p.started, name: name, path: path, resident: footprint ?? rss, cpu: cpu)
            sample.rss = rss
            sample.uid = p.uid
            sample.responsible = p.responsible
            sample.parent = p.parent
            sample.cwd = withUnsafeBytes(of: &processBuffer[index].cwd) { let value = String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self); return value.isEmpty ? nil : value }
            if let agent = context(for: p, name: name, path: path, cwd: sample.cwd) { sample.configDir = agent.configDir; sample.pane = agent.pane; sample.agentEnvironmentRead = agent.read }
            if let old = previousProcesses[p.pid], old.identity == p.started, p.started > 0, let written = old.writes, p.io_ok != 0, p.disk_written >= written, let elapsed, elapsed > 0 {
                sample.writesPerSecond = Double(p.disk_written - written) / elapsed
            }
            return sample
        }
        let live = Set(samples.map(\.pid))
        agentContext = agentContext.filter { live.contains($0.key) }
        var groups = Attribution.groups(samples, metadata: &metadata)
        if PulseEnvironment.demoEnabled() { groups = DemoData.anonymizeGroups(groups) }
        previousProcesses = current; previousProcessTime = now
        s.groups = groups; s.processCount = count; s.limitedProcessCount = samples.filter { $0.resident == nil }.count
        s.topMemoryGroup = groups.filter { $0.resident != nil }.max { ($0.resident ?? 0) < ($1.resident ?? 0) }?.title
        s.processSampleDate = s.date
    }
}

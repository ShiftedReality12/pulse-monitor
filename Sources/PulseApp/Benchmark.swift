import Foundation
import Darwin
import PulseCore

enum Benchmark {
    static func footprint() -> UInt64? { memory()?.current }
    static func memory() -> (current: UInt64, peak: UInt64, graphics: Int64?, graphicsUncharged: Int64?)? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ledgerEnd = MemoryLayout.offset(of: \task_vm_info_data_t.ledger_tag_graphics_nofootprint_compressed)! + MemoryLayout<Int64>.size
        let hasLedgers = Int(count) * MemoryLayout<integer_t>.size >= ledgerEnd
        return (info.phys_footprint, UInt64(max(0, info.ledger_phys_footprint_peak)),
                hasLedgers ? info.ledger_tag_graphics_footprint + info.ledger_tag_graphics_footprint_compressed : nil,
                hasLedgers ? info.ledger_tag_graphics_nofootprint + info.ledger_tag_graphics_nofootprint_compressed : nil)
    }
    static func usage() -> rusage { var value = rusage(); guard getrusage(RUSAGE_SELF, &value) == 0 else { perror("getrusage"); exit(1) }; return value }
    static func cpu(_ usage: rusage) -> Double {
        Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }
    static func run(seconds: Double, visible: Bool) {
        let start = ProcessInfo.processInfo.systemUptime, initial = usage()
        let session = SamplingSession()
        var samples = 0
        var checkpoints: [[String: Double]] = []
        let interval = SamplingPolicy.interval(visible: visible)
        while true {
            autoreleasepool {
                let (snapshot, _) = session.sample(visible: visible)
                if snapshot.pressure == .critical { fputs("Memory guard: red pressure\n", stderr); exit(75) }
            }
            samples += 1
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            if usage().ru_maxrss > 4_000_000_000 || (footprint() ?? 0) > 4_000_000_000 { fputs("Memory guard: benchmark exceeds 4 GB\n", stderr); exit(75) }
            if elapsed >= Double(checkpoints.count + 1) * 120 {
                var checkpoint = ["wall_seconds": elapsed]
                if let bytes = footprint() { checkpoint["phys_footprint_mb"] = Double(bytes) / 1e6 }
                checkpoints.append(checkpoint)
            }
            if elapsed >= seconds { break }
            Thread.sleep(forTimeInterval: min(interval, seconds - elapsed))
        }
        let final = usage(), wall = ProcessInfo.processInfo.systemUptime - start
        var output: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "executable": EvidencePath.display(CommandLine.arguments[0]), "sampling_interval_seconds": interval, "process_interval_seconds": visible ? SamplingPolicy.processInterval(visible: true) : 0, "version": "v5", "scope": "headless real SamplingSession + bounded history/chart preparation; no GUI renderer", "visible": visible, "requested_seconds": seconds, "wall_seconds": wall, "cpu_seconds": cpu(final) - cpu(initial), "max_rss_mb": Double(final.ru_maxrss) / 1e6, "samples": samples, "history_count": session.history.count, "history_capacity": session.history.capacity, "chart_point_limit": 120, "checkpoints": checkpoints]
        if let bytes = footprint() { output["phys_footprint_mb"] = Double(bytes) / 1e6 }
        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }
    }
}

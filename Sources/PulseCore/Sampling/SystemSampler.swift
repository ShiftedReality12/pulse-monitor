import Foundation
import Darwin
import CSensors

final class SystemSampler {
    private var previousWrites: (bytes: UInt64, time: Double)?
    private var previousCPU: [CPUTicks] = []
    private var cpuBuffer = [PulseCPU](repeating: PulseCPU(), count: 256)
    private var sensorSampleDate: Date?
    private var cachedSensors: PulseSensors?
    private var cachedThermal = PulseThermal(warning_level: -1, speed_limit: -1, scheduler_limit: -1, available_cpus: -1)
    private var lastSensorTime: TimeInterval?
    private var lastBaselineSync = -TimeInterval.infinity
    private var cachedWrittenToday: UInt64?
    private var cachedBaselineStatus = "Unavailable"
    private let dayFormatter: DateFormatter = {
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.locale = Locale(identifier: "en_US_POSIX")
        return day
    }()
    private let performanceCoreCount = Int(pulse_perf_count(0))
    private let efficiencyCoreCount = Int(pulse_perf_count(1))
    private let baselineURL: URL
    init(baselineURL: URL?) {
        self.baselineURL = baselineURL ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Pulse/daily-baseline.json")
    }
    func sample() -> Snapshot {
        var s = Snapshot()
        let now = ProcessInfo.processInfo.systemUptime
        let n = Int(pulse_cpu(&cpuBuffer, Int32(cpuBuffer.count)))
        let ticks = cpuBuffer.prefix(n).map { CPUTicks(user: $0.user, system: $0.system, idle: $0.idle, nice: $0.nice) }
        if ticks.count == previousCPU.count && !ticks.isEmpty {
            let usages = zip(ticks, previousCPU).map { $0.usage(since: $1) }
            func average(_ values: ArraySlice<Double?>) -> Double? {
                let valid = values.compactMap { $0 }; return valid.count == values.count && !valid.isEmpty ? valid.reduce(0, +) / Double(valid.count) : nil
            }
            s.cpu = average(usages[...])
            // Darwin CPU indices on Apple Silicon enumerate E cores then P cores.
            let pCount = performanceCoreCount, eCount = efficiencyCoreCount
            if pCount + eCount == n && pCount > 0 && eCount > 0 {
                s.efficiencyCPU = average(usages[..<eCount]); s.performanceCPU = average(usages[eCount...])
            }
        }
        previousCPU = ticks
        let memory = pulse_memory()
        if memory.vm_ok != 0 { s.memoryTotal = memory.total; s.memoryUsed = memory.used; s.compressed = memory.compressed }
        if memory.swap_ok != 0 { s.swap = memory.swap }
        if memory.free_percent >= 0 { s.memoryFreePercent = memory.free_percent }
        s.pressure = Pressure.classify(Int(memory.pressure_level))
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: s.thermal = "Nominal"
        case .fair: s.thermal = "Warm"
        case .serious: s.thermal = "Serious"
        case .critical: s.thermal = "Critical"
        @unknown default: s.thermal = "Unavailable"
        }
        if lastSensorTime.map({ now - $0 >= 10 }) ?? true {
            cachedSensors = pulse_sensors(); cachedThermal = pulse_thermal(); lastSensorTime = now; sensorSampleDate = s.date
        }
        var sensors = cachedSensors ?? PulseSensors()
        s.temperature = sensors.celsius.isFinite ? sensors.celsius : nil
        s.cpuDieTemperature = sensors.cpu_die.isFinite ? sensors.cpu_die : nil
        s.fans = withUnsafeBytes(of: &sensors.fans) { raw in Array(raw.bindMemory(to: Double.self).prefix(Int(sensors.fan_count))) }
        s.sensorStatus = withUnsafeBytes(of: &sensors.status) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        s.sensorSampleDate = sensorSampleDate
        s.cpuSpeedLimit = cachedThermal.speed_limit >= 0 ? Int(cachedThermal.speed_limit) : nil
        s.thermalWarning = cachedThermal.warning_level >= 0 ? Int(cachedThermal.warning_level) : nil
        var disk = statfs()
        if statfs("/", &disk) == 0 {
            s.diskFree = UInt64(disk.f_bavail) * UInt64(disk.f_bsize)
            s.diskTotal = UInt64(disk.f_blocks) * UInt64(disk.f_bsize)
        }
        var written: UInt64 = 0
        if pulse_disk_writes(&written) != 0 {
            s.bytesWritten = written
            if let old = previousWrites, now > old.time, written >= old.bytes { s.writesPerSecond = Double(written - old.bytes) / (now - old.time) }
            previousWrites = (written, now)
            let boot = pulse_boot_time()
            if boot > 0 {
                // The baseline file is shared with other Pulse builds. Re-read it at most twice a minute.
                if now - lastBaselineSync >= 30 {
                    lastBaselineSync = now
                    do {
                        // Lock the directory inode so atomic baseline replacement cannot break mutual exclusion.
                        let directory = baselineURL.deletingLastPathComponent()
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        let fd = open(directory.path, O_RDONLY)
                        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
                        defer { close(fd) }
                        guard flock(fd, LOCK_EX) == 0 else { throw CocoaError(.fileWriteNoPermission) }
                        defer { flock(fd, LOCK_UN) }
                        let old = (try? Data(contentsOf: baselineURL)).flatMap { try? JSONDecoder().decode(DailyBaseline.self, from: $0) }
                        var baseline = old ?? DailyBaseline(day: dayFormatter.string(from: s.date), boot: boot, bytes: written)
                        let daily = baseline.update(day: dayFormatter.string(from: s.date), boot: boot, bytes: written)
                        if baseline != old { try JSONEncoder().encode(baseline).write(to: baselineURL, options: .atomic) }
                        s.writtenToday = daily; s.baselineStatus = "Since first reading today"
                    } catch { s.baselineStatus = "Daily baseline unavailable: \(error.localizedDescription)" }
                    cachedWrittenToday = s.writtenToday
                    cachedBaselineStatus = s.baselineStatus
                } else {
                    s.writtenToday = cachedWrittenToday
                    s.baselineStatus = cachedBaselineStatus
                }
            }
        } else { previousWrites = nil }
        return s
    }
}

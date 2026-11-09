import Foundation
import Darwin
import CSensors

/// Explicit utility reader; every child starts in its own process group.
enum ProviderCommand {
    static func read(executable: URL, arguments: [String], timeout: Double = 1, limit: Int = 65_536) -> String? {
        let strings = ([executable.path] + arguments).map { strdup($0) }
        defer { for string in strings { free(string) } }
        var argv = strings + [nil], fd: Int32 = -1
        let pid = argv.withUnsafeMutableBufferPointer { pulse_spawn_group(executable.path, $0.baseAddress, &fd) }
        guard pid > 0 else { return nil }
        defer { close(fd) }
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { kill(-pid, SIGKILL); waitpid(pid, nil, 0); return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + min(10, max(0.01, timeout))
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096), valid = true
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                guard data.count + count <= limit else { valid = false; break }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 { break }
            else if errno != EAGAIN && errno != EINTR { valid = false; break }
            if Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline { valid = false; break }
            if count < 0 { Thread.sleep(forTimeInterval: 0.005) }
        }
        var status: Int32 = 0, reaped = false
        while valid && ProcessInfo.processInfo.systemUptime < deadline {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid { reaped = true; break }
            if result < 0 { valid = false; break }
            Thread.sleep(forTimeInterval: 0.005)
        }
        if !reaped { valid = false; kill(-pid, SIGKILL); waitpid(pid, &status, 0) }
        return valid && pulse_process_succeeded(status) != 0 ? String(data: data, encoding: .utf8) : nil
    }
}

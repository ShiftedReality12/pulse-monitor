import Foundation

/// Test and demonstration overrides for optional-provider detection. They only point detection somewhere else; no file is moved.
public enum PulseEnvironment {
    /// `PULSE_DEMO=1` feeds generic sample labels for README screenshots. Unset leaves normal behaviour unchanged.
    public static func demoEnabled(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["PULSE_DEMO"] == "1"
    }
    public static func providerHome(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        environment["PULSE_PROVIDER_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil } ?? FileManager.default.homeDirectoryForCurrentUser
    }
    /// True when detection was pointed somewhere else, so well-known install folders must not be searched.
    public static func providerPathOverridden(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["PULSE_PROVIDER_PATH"] != nil
    }
    public static func providerPath(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        environment["PULSE_PROVIDER_PATH"] ?? environment["PATH"] ?? ""
    }
    /// Absolute path to an optional usage reader. Defaults to `<provider home>/bin/usage`.
    public static func usageExecutable(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["PULSE_USAGE_EXECUTABLE"], path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return providerHome(environment).appendingPathComponent("bin/usage")
    }
}

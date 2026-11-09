import Foundation

/// Optional integrations describe availability without changing core sampler contracts.
public protocol PulseProvider: Sendable {
    var id: String { get }
    var cadence: Double { get }
    var section: String? { get }
    func isAvailable() -> Bool
}
public struct ProviderRegistry: Sendable {
    private let providers: [any PulseProvider]
    private var checkedAt = -Double.infinity
    public private(set) var available: [any PulseProvider] = []
    public private(set) var detections = 0
    public var sections: [String] { available.compactMap(\.section) }
    public init(providers: [any PulseProvider]) { self.providers = providers }
    public static func standard() -> Self {
        Self(providers: [HerdrProvider(), AgentAccountsProvider(), UsageStripProvider()])
    }
    public mutating func refresh(at time: Double = ProcessInfo.processInfo.systemUptime) {
        guard time - checkedAt >= 900 else { return }
        checkedAt = time; detections += 1
        available = providers.filter { $0.isAvailable() }
    }
}

import Foundation

public struct DailyBaseline: Codable, Equatable, Sendable {
    public var day: String
    public var boot: UInt64
    public var bytes: UInt64
    public init(day: String, boot: UInt64, bytes: UInt64) { self.day = day; self.boot = boot; self.bytes = bytes }
    public mutating func update(day: String, boot: UInt64, bytes: UInt64) -> UInt64 {
        if self.day != day || self.boot != boot || bytes < self.bytes { self = Self(day: day, boot: boot, bytes: bytes) }
        return bytes - self.bytes
    }
}

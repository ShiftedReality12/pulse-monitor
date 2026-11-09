import Foundation
import Testing
@testable import PulseCore

@Test func appDoesNotUseGPUCanvasOrUntestedCharts() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = root.appendingPathComponent("Sources")
    let files = try #require(FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil))
    for case let file as URL in files where file.pathExtension == "swift" {
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.range(of: #"\bCanvas\s*(?:\{|\()"#, options: .regularExpression) == nil, "\(file.lastPathComponent) allocates the GPU plotting pool")
        #expect(!text.contains("import Charts"), "\(file.lastPathComponent) uses an unmeasured plot renderer")
    }
}

import AppKit
import Testing

@MainActor @Test func heroStatusSymbolsExistOnThisMacOS() {
    for name in ["internaldrive", "thermometer.high", "memorychip", "cpu", "questionmark.circle", "checkmark.seal"] {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "Missing hero glyph: \(name)")
    }
}

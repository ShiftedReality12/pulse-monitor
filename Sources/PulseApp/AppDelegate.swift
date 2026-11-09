import SwiftUI
import AppKit
import PulseCore

@MainActor final class GlancePanel: NSPanel { override var canBecomeKey: Bool { true } }
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NSPanel?
    private var overview: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--show-glance") {
            let panel = WindowHosts.glance(monitor: Monitor.shared, openOverview: showOverview).window
            panel.delegate = self
            panel.center(); panel.makeKeyAndOrderFront(nil); self.panel = panel as? NSPanel; NSApp.activate(ignoringOtherApps: true)
        }
        if CommandLine.arguments.contains("--show-window") { showOverview() }
        promptForFullDiskAccessIfNeeded()
    }
    /// One prompt. "Don't ask again" and "Open Settings" both suppress later launches. "Not now" asks next launch.
    private func promptForFullDiskAccessIfNeeded() {
        let key = "pulse.fda.dontAskAgain"
        guard !UserDefaults.standard.bool(forKey: key), !FullDiskAccess.granted() else { return }
        let alert = NSAlert()
        alert.messageText = "Full Disk Access is optional"
        alert.informativeText = "Some folders stay hidden until Pulse is allowed in Privacy & Security. Pulse cannot grant this itself. In the list it appears as Pulse."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Don't ask again")
        alert.addButton(withTitle: "Not now")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            UserDefaults.standard.set(true, forKey: key)
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
        case .alertSecondButtonReturn:
            UserDefaults.standard.set(true, forKey: key)
        default:
            break
        }
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === overview { Monitor.shared.visibility("window", shown: false); overview = nil }
        if window === panel { Monitor.shared.visibility("glance", shown: false); panel = nil }
        window.contentView = nil
    }
    func applicationDidHide(_ notification: Notification) { Monitor.shared.applicationVisibility(false) }
    func applicationDidUnhide(_ notification: Notification) { Monitor.shared.applicationVisibility(true) }
    func windowDidMiniaturize(_ notification: Notification) {
        if notification.object as? NSWindow === overview { Monitor.shared.visibility("window", shown: false) }
    }
    func windowDidDeminiaturize(_ notification: Notification) {
        if notification.object as? NSWindow === overview { Monitor.shared.visibility("window", shown: true) }
    }
    func showOverview() {
        if overview == nil {
            let window = WindowHosts.overview(monitor: Monitor.shared).window
            window.delegate = self; window.center(); overview = window
        }
        Monitor.shared.visibility("window", shown: true)
        overview?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

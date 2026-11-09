import AppKit
import SwiftUI

struct HostedSurface {
    let window: NSWindow
    let host: NSView
    let initialSize: NSSize
}
/// Shared by the application and the benchmark: the real window/hosting/constraint seam.
@MainActor enum WindowHosts {
    static func glance(monitor: Monitor, openOverview: @escaping @MainActor () -> Void, legacySizing: Bool = false) -> HostedSurface {
        let host = MeasuredHostingView(rootView: GlanceView(monitor: monitor, openOverview: openOverview).ignoresSafeArea())
        host.diagnosticName = "glance"
        let size = host.fittingSize // One startup measurement; never queried on a value update.
        if !legacySizing { host.sizingOptions = [] }
        let panel = GlancePanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Pulse Glance"; panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { panel.standardWindowButton(button)?.isHidden = true }
        let chrome = backdrop(size: size, material: .sidebar)
        chrome.addSubview(host)
        if legacySizing {
            host.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: chrome.leadingAnchor), host.trailingAnchor.constraint(equalTo: chrome.trailingAnchor), host.topAnchor.constraint(equalTo: chrome.topAnchor), host.bottomAnchor.constraint(equalTo: chrome.bottomAnchor)])
        } else {
            host.frame = chrome.bounds; host.autoresizingMask = [.width, .height]
        }
        panel.contentView = chrome; panel.setContentSize(size)
        return HostedSurface(window: panel, host: host, initialSize: size)
    }
    static func overview(monitor: Monitor, legacySizing: Bool = false) -> HostedSurface {
        let size = NSSize(width: 1000, height: 760)
        let host = MeasuredHostingView(rootView: PulseWindow(monitor: monitor))
        host.diagnosticName = "overview"
        if !legacySizing { host.sizingOptions = [] }
        host.frame = NSRect(origin: .zero, size: size); host.autoresizingMask = [.width, .height]
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Pulse"; window.isReleasedWhenClosed = false
        if !legacySizing { window.contentMinSize = NSSize(width: 850, height: 650) }
        window.isOpaque = false; window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        let chrome = backdrop(size: size, material: .underWindowBackground)
        chrome.addSubview(host)
        window.contentView = chrome
        return HostedSurface(window: window, host: host, initialSize: size)
    }
    private static func backdrop(size: NSSize, material: NSVisualEffectView.Material) -> NSVisualEffectView {
        let view = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        view.material = material; view.blendingMode = .behindWindow; view.state = .active
        view.autoresizingMask = [.width, .height]
        return view
    }
}
/// Opt-in counters distinguish host layout work from an explicit layoutIfNeeded request.
@MainActor final class MeasuredHostingView<Content: View>: NSHostingView<Content> {
    var diagnosticName = "host"
    override var isOpaque: Bool { false }
    override func updateConstraints() {
        RenderDiagnostics.shared.record(diagnosticName + ".constraints")
        super.updateConstraints()
    }
    override func layout() {
        RenderDiagnostics.shared.record(diagnosticName + ".layout")
        super.layout()
    }
    override var intrinsicContentSize: NSSize {
        RenderDiagnostics.shared.record(diagnosticName + ".intrinsic")
        return super.intrinsicContentSize
    }
    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { RenderDiagnostics.shared.record(diagnosticName + ".resize") }
        super.setFrameSize(newSize)
    }
}

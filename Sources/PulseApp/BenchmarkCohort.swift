import AppKit
import QuartzCore

@MainActor enum BenchmarkCohort {
    static func valid(_ surfaces: [HostedSurface]) -> Bool {
        !NSScreen.screens.isEmpty && !NSApp.isHidden && surfaces.allSatisfy { surface in
            surface.window.isVisible && !surface.window.isMiniaturized &&
            surface.window.occlusionState.contains(.visible) &&
            NSScreen.screens.contains { screen in screen.visibleFrame.intersects(surface.window.frame) }
        }
    }
    static func report(_ surfaces: [HostedSurface]) -> [[String: Any]] {
        surfaces.map { surface in
            ["title": surface.window.title, "visible": surface.window.isVisible,
             "miniaturized": surface.window.isMiniaturized, "occlusion_state": surface.window.occlusionState.rawValue,
             "frame": NSStringFromRect(surface.window.frame), "screen_count": NSScreen.screens.count,
             "toolbar_visible": surface.window.toolbar?.isVisible ?? false,
             "native_close_button_in_frame": surface.window.standardWindowButton(.closeButton).map { button in
                 let rect = button.convert(button.bounds, to: nil)
                 return !button.isHidden && rect.minX >= 0 && rect.minY >= 0 &&
                     rect.maxX <= surface.window.frame.width && rect.maxY <= surface.window.frame.height
             } ?? false]
        }
    }
    static func layers(_ surfaces: [HostedSurface]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        func visit(_ layer: CALayer, path: String) {
            if layer.bounds.width * layer.bounds.height > 10_000 {
                result.append(["path": path, "class": NSStringFromClass(type(of: layer)),
                               "bounds": NSStringFromRect(layer.bounds), "scale": layer.contentsScale,
                               "format": layer.contentsFormat.rawValue, "rasterized": layer.shouldRasterize])
            }
            for (index, child) in (layer.sublayers ?? []).enumerated() { visit(child, path: path + "/\(index)") }
        }
        for surface in surfaces { if let layer = surface.host.layer { visit(layer, path: surface.window.title) } }
        return result
    }
}

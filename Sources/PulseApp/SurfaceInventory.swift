import AppKit
import QuartzCore

/// Geometry models are not allocation measurements: nested layers may share backing.
@MainActor enum SurfaceInventory {
    static func capture(_ surfaces: [HostedSurface]) -> [String: Any] {
        var layers: [[String: Any]] = [], views: [[String: Any]] = [], windows: [[String: Any]] = []
        var visited = Set<ObjectIdentifier>()
        func area(_ size: CGSize, scale: CGFloat) -> Double {
            Double(max(0, size.width) * max(0, size.height) * scale * scale * 4)
        }
        func visitLayer(_ layer: CALayer, path: String) {
            guard visited.insert(ObjectIdentifier(layer)).inserted else { return }
            layers.append([
                "path": path, "class": NSStringFromClass(type(of: layer)), "name": layer.name ?? "",
                "width": layer.bounds.width, "height": layer.bounds.height, "scale": layer.contentsScale,
                "rgba8_single_buffer_bytes": area(layer.bounds.size, scale: layer.contentsScale),
                "rgba8_at_2x_bytes": area(layer.bounds.size, scale: 2),
                "has_mask": layer.mask != nil, "clips": layer.masksToBounds,
                "rasterized": layer.shouldRasterize, "filters": layer.filters?.count ?? 0,
                "shadow_without_path": layer.shadowOpacity > 0 && layer.shadowPath == nil,
                "has_contents": layer.contents != nil, "animation_count": layer.animationKeys()?.count ?? 0
            ])
            if let mask = layer.mask { visitLayer(mask, path: path + "/mask") }
            for (index, child) in (layer.sublayers ?? []).enumerated() { visitLayer(child, path: path + "/\(index)") }
        }
        func visitView(_ view: NSView, path: String) {
            views.append([
                "path": path, "class": NSStringFromClass(type(of: view)),
                "width": view.bounds.width, "height": view.bounds.height,
                "is_glass": view is NSGlassEffectView, "is_visual_effect": view is NSVisualEffectView,
                "rgba8_at_2x_bytes": area(view.bounds.size, scale: 2)
            ])
            if let layer = view.layer { visitLayer(layer, path: path + "/layer") }
            for (index, child) in view.subviews.enumerated() { visitView(child, path: path + "/view\(index)") }
        }
        for surface in surfaces {
            windows.append(["title": surface.window.title, "width": surface.window.frame.width,
                            "height": surface.window.frame.height, "scale": surface.window.backingScaleFactor,
                            "rgba8_at_2x_bytes": area(surface.window.frame.size, scale: 2)])
            if let content = surface.window.contentView { visitView(content.superview ?? content, path: surface.window.title) }
        }
        return ["scope": "end-of-run native view/layer geometry including masks and window chrome; byte values model one RGBA8 buffer, not unique allocations",
                "windows": windows, "views": views, "layers": layers,
                "mask_count": layers.filter { $0["has_mask"] as? Bool == true }.count,
                "glass_view_count": views.filter { $0["is_glass"] as? Bool == true }.count,
                "visual_effect_view_count": views.filter { $0["is_visual_effect"] as? Bool == true }.count]
    }
}

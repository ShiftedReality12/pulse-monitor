import SwiftUI

struct GlanceBoundsKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
extension View {
    @ViewBuilder func renderBounds(_ key: String, enabled: Bool = true, space: String = "glance-viewport") -> some View {
        if enabled && RenderDiagnostics.shared.enabled {
            background {
                GeometryReader { proxy in
                    Color.clear.preference(key: GlanceBoundsKey.self, value: [key: proxy.frame(in: .named(space))])
                }
            }
        } else { self }
    }
}

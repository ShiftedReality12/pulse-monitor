import AppKit
import QuartzCore
import SwiftUI

/// Mask-free vector strokes; only the arc endpoint animates, never the SwiftUI layout.
struct LayerRing: NSViewRepresentable {
    let fraction: Double
    let tint: Color
    let animate: Bool
    func makeNSView(context: Context) -> RingLayerView { RingLayerView(frame: .zero) }
    func updateNSView(_ view: RingLayerView, context: Context) {
        view.configure(fraction: CGFloat(fraction), tint: NSColor(tint), animate: animate)
    }
}
@MainActor final class RingLayerView: NSView {
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()
    private var lastSize = NSSize.zero
    private var target: CGFloat?
    private var tint = NSColor.systemTeal
    private var resolvedTint: CGColor?
    private var resolvedTrack: CGColor?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        track.fillColor = nil; track.lineWidth = 6
        arc.fillColor = nil; arc.lineWidth = 6; arc.lineCap = .round
        track.name = "Pulse.ring.track"; arc.name = "Pulse.ring.stroke"
        layer?.addSublayer(track); layer?.addSublayer(arc)
    }
    required init?(coder: NSCoder) { nil }
    func configure(fraction: CGFloat, tint: NSColor, animate: Bool) {
        self.tint = tint; updateColors()
        if !animate { arc.removeAnimation(forKey: "value") }
        guard fraction != target else { return }
        let previous = arc.presentation()?.strokeEnd ?? arc.strokeEnd
        let hadTarget = target != nil; target = fraction
        CATransaction.begin(); CATransaction.setDisableActions(true)
        arc.strokeEnd = fraction
        CATransaction.commit()
        RenderDiagnostics.shared.record("ring.layer.target")
        if animate && hadTarget && window?.isVisible == true {
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = previous; animation.toValue = fraction
            animation.duration = 0.22; animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            arc.add(animation, forKey: "value")
            RenderDiagnostics.shared.record("ring.layer.animation")
        }
    }
    override func layout() {
        super.layout()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.frame = bounds; arc.frame = bounds
        let radius = max(0, (min(bounds.width, bounds.height) - 6) / 2)
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius, startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
        track.path = path; arc.path = path
        CATransaction.commit()
        RenderDiagnostics.shared.record("ring.layer.geometry")
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { arc.removeAllAnimations() }
    }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = tint.cgColor
            let trackColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            guard color != resolvedTint || trackColor != resolvedTrack else { return }
            resolvedTint = color; resolvedTrack = trackColor
            CATransaction.begin(); CATransaction.setDisableActions(true)
            track.strokeColor = trackColor
            arc.strokeColor = color
            CATransaction.commit()
            RenderDiagnostics.shared.record("ring.layer.colors")
        }
    }
}

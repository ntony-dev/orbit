import AppKit
import QuartzCore
import SwiftUI

// Equalizer bars that rise and fall while playing; a still pause glyph otherwise. The pill shows this whenever
// music plays, which is Orbit's resting state, so the motion is a Core Animation loop committed once and run by
// the render server. A SwiftUI symbol effect here re-rendered the hosting view and the glass every frame and cost
// a quarter of a core while the app sat idle.
struct PlayingIndicator: View {
    let isPlaying: Bool
    // Over artwork the bars are drawn in white on a scrim, where the accent could vanish.
    var tint: Color?

    @Environment(\.orbitTheme) private var theme

    var body: some View {
        ZStack {
            if isPlaying {
                EqualizerBars(color: tint ?? theme.accent, animates: !theme.reducesMotion)
            } else {
                Image(systemName: "pause.fill")
                    .font(.system(size: OrbitTokens.Icon.small, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: OrbitTokens.Icon.indicator)
        .transition(.opacity)
        .animation(theme.animation(OrbitTokens.Motion.hover), value: isPlaying)
        .accessibilityHidden(true)
    }
}

private struct EqualizerBars: NSViewRepresentable {
    let color: Color
    let animates: Bool

    func makeNSView(context: Context) -> EqualizerView {
        EqualizerView()
    }

    func updateNSView(_ view: EqualizerView, context: Context) {
        view.update(color: color.resolve(in: context.environment).cgColor, animates: animates)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualizerView, context: Context) -> CGSize? {
        EqualizerView.size
    }
}

final class EqualizerView: NSView {
    // Two-point bars stay crisp on a 1x display; the resting heights are what reduced motion and snapshots show.
    static let barWidth: CGFloat = 2.5
    static let barSpacing: CGFloat = 2
    static let restingHeights: [CGFloat] = [0.55, 1, 0.7, 0.4]
    static let size = CGSize(
        width: CGFloat(restingHeights.count) * barWidth + CGFloat(restingHeights.count - 1) * barSpacing,
        height: OrbitTokens.Icon.indicator - 2
    )
    // Each bar loops over its own cycle so the group never visibly repeats in step.
    private static let cycles: [(duration: CFTimeInterval, values: [CGFloat])] = [
        (1.1, [0.55, 0.3, 0.9, 0.45, 0.55]),
        (0.9, [1, 0.5, 0.75, 0.35, 1]),
        (1.3, [0.7, 1, 0.4, 0.85, 0.7]),
        (1.0, [0.4, 0.75, 0.3, 0.95, 0.4]),
    ]
    private static let animationKey = "orbit.equalizer"

    private let bars: [CALayer] = restingHeights.map { _ in CALayer() }
    private var animates = false

    init() {
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        wantsLayer = true
        for bar in bars {
            bar.cornerRadius = Self.barWidth / 2
            layer?.addSublayer(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize { Self.size }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: bounds.height)
            bar.position = CGPoint(
                x: CGFloat(index) * (Self.barWidth + Self.barSpacing) + Self.barWidth / 2 + (bounds.width - Self.size.width) / 2,
                y: bounds.midY
            )
            bar.transform = CATransform3DMakeScale(1, Self.restingHeights[index], 1)
        }
        CATransaction.commit()
    }

    func update(color: CGColor, animates: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bars.forEach { $0.backgroundColor = color }
        CATransaction.commit()
        guard animates != self.animates else { return }
        self.animates = animates
        applyAnimations()
    }

    // A layer leaving the window can lose its animations, so they are reattached whenever the view returns.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAnimations()
    }

    private func applyAnimations() {
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: Self.animationKey)
            guard animates, window != nil else { continue }
            let cycle = Self.cycles[index]
            let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
            animation.values = cycle.values
            animation.duration = cycle.duration
            animation.calculationMode = .cubic
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            // Bars this small read as smooth at a low rate, which keeps the window server's compositing cheap too.
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 24)
            bar.add(animation, forKey: Self.animationKey)
        }
    }
}

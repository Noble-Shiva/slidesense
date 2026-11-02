import AppKit
import Foundation

// MARK: - Metrics

/// Geometry of the 18×18 menu bar artwork, in points.
///
/// The outline is a thin trackpad; each inner edge carries a bar whose height
/// shows the live level of whatever that edge controls. Heights snap to whole
/// pixels on a 2× display (0.5 pt), which gives 16 visible steps — the same
/// resolution as the system volume and brightness keys — and means the image
/// only has to be redrawn when a level moves far enough to change a pixel.
enum StatusItemIconMetrics {
    static let size = NSSize(width: 18, height: 18)

    static let outlineRect = NSRect(x: 3.25, y: 2.25, width: 11.5, height: 13.5)
    static let outlineRadius: CGFloat = 2.75
    static let outlineLineWidth: CGFloat = 1.5

    static let barWidth: CGFloat = 1.5
    static let leftBarX: CGFloat = 4.5
    static let rightBarX: CGFloat = 12

    /// Bars grow upwards from here, like the fill of a level meter.
    static let barBottom: CGFloat = 4.5
    /// A level of zero (or a muted output) still shows a round dot, so each
    /// edge stays recognisable.
    static let minimumBarHeight: CGFloat = 1.5
    static let maximumBarHeight: CGFloat = 9

    /// Bar heights snap to this increment: one pixel at 2×.
    static let heightQuantum: CGFloat = 0.5

    /// Opacity of the whole glyph while SlideSense is switched off.
    static let disabledAlpha: CGFloat = 0.42

    /// The bar height for a level in 0…1. Out-of-range input is clamped and
    /// the result is snapped to `heightQuantum`.
    static func barHeight(for level: Double) -> CGFloat {
        let clamped = CGFloat(min(max(level.isFinite ? level : 0, 0), 1))
        let raw = minimumBarHeight + clamped * (maximumBarHeight - minimumBarHeight)
        return (raw / heightQuantum).rounded() * heightQuantum
    }
}

// MARK: - State

/// Everything the menu bar glyph depends on. Two equal states draw identical
/// images, so the controller only redraws when this value changes.
struct StatusItemIconState: Equatable {
    var leftBarHeight: CGFloat
    var rightBarHeight: CGFloat
    var enabled: Bool

    init(leftLevel: Double, rightLevel: Double, enabled: Bool) {
        leftBarHeight = StatusItemIconMetrics.barHeight(for: leftLevel)
        rightBarHeight = StatusItemIconMetrics.barHeight(for: rightLevel)
        self.enabled = enabled
    }
}

// MARK: - Drawing

enum StatusItemIcon {
    /// Draws the template glyph for a state. Template images are tinted by the
    /// menu bar, so black-with-alpha is the only colour used.
    static func image(for state: StatusItemIconState) -> NSImage {
        typealias M = StatusItemIconMetrics

        let image = NSImage(size: M.size, flipped: false) { _ in
            let alpha = state.enabled ? 1 : M.disabledAlpha
            let color = NSColor.black.withAlphaComponent(alpha)
            color.setStroke()
            color.setFill()

            let outline = NSBezierPath(
                roundedRect: M.outlineRect,
                xRadius: M.outlineRadius,
                yRadius: M.outlineRadius
            )
            outline.lineWidth = M.outlineLineWidth
            outline.stroke()

            let radius = M.barWidth / 2
            for (x, height) in [(M.leftBarX, state.leftBarHeight), (M.rightBarX, state.rightBarHeight)] {
                let bar = NSRect(x: x, y: M.barBottom, width: M.barWidth, height: height)
                NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

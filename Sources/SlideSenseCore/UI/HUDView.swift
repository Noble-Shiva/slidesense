import AppKit
import QuartzCore

/// Every number the HUD is built from, in one place.
///
/// The proportions follow Apple's own volume/brightness OSD: a fixed-size
/// capsule with an icon on the leading side and a level bar that fills the
/// remaining width, with equal optical margins on both sides.
enum HUDMetrics {

    // Panel

    static let panelWidth: CGFloat = 210
    static let panelHeight: CGFloat = 60
    static var panelSize: NSSize {
        NSSize(width: panelWidth, height: panelHeight)
    }
    static let cornerRadius: CGFloat = 16

    // Horizontal rhythm

    /// Optical margin from the panel edge to the icon box and from the bar's
    /// trailing edge to the panel edge. Both are 14, so the content reads as
    /// centred inside the capsule.
    static let contentInset: CGFloat = 14
    /// Square box the level symbol is optically centred in. It is wider than
    /// the glyph on purpose: SF Symbols have uneven bounding boxes and the box
    /// keeps the speaker/sun from shifting toward the bar.
    static let iconBoxWidth: CGFloat = 22
    static let iconBoxHeight: CGFloat = 22
    /// Space between the icon box and the leading edge of the bar.
    static let gap: CGFloat = 12

    // Level bar

    static let barHeight: CGFloat = 8
    static let barCornerRadius: CGFloat = 4
    /// A non-zero level always shows at least one fully rounded cap, so
    /// "almost silent" still reads as a bar rather than a speck.
    static let minimumVisibleLevel: Double = 0.002

    // Media glyph

    static let mediaIconWidth: CGFloat = 40
    static let mediaIconHeight: CGFloat = 30

    // Symbols

    static let levelSymbolPointSize: CGFloat = 17
    static let mediaSymbolPointSize: CGFloat = 22

    // Motion

    static let fillAnimationDuration: CFTimeInterval = 0.15

    /// Leading edge of the bar: icon box plus the gap.
    static var barOriginX: CGFloat {
        contentInset + iconBoxWidth + gap
    }
}

/// The pill the HUD draws itself into.
///
/// On macOS 26+ the background is a real `NSGlassEffectView` – the same liquid
/// glass capsule the system OSD uses – with the content view embedded in the
/// glass. On macOS 13–15 it falls back to `NSVisualEffectView(.hudWindow)`.
/// The overlay owns the symbol and the level bar so they always sit above the
/// background. Everything is created once: rapid calls to
/// `HUDController.show(...)` only move the fill layer and swap a couple of
/// colours.
final class HUDView: NSView {

    static let preferredSize = HUDMetrics.panelSize

    /// The material background: glass on macOS 26+, a visual effect view
    /// before that. Exposed for layout tests and snapshot rendering.
    let backgroundView: NSView
    let overlay = NSView()
    let trackLayer = CALayer()
    let fillLayer = CALayer()
    let iconView = NSImageView(frame: .zero)

    private(set) var showsLevel = true
    private(set) var level: Double = 0
    private(set) var isMuted = false
    /// The SF Symbol currently installed, so tests can assert the state
    /// mapping without reaching into the image view.
    private(set) var iconSymbolName = ""

    private var iconKey = ""
    private var currentContentColor: NSColor?
    private var currentMuted = false

    // MARK: - Lifecycle

    override init(frame frameRect: NSRect) {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            // `NSGlassEffectView` exposes a plain `cornerRadius` (no
            // `cornerCurve`); the system glass is continuous by design.
            glass.cornerRadius = HUDMetrics.cornerRadius
            glass.style = .regular
            // No tint: the default glass is the system OSD look.
            backgroundView = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.isEmphasized = true
            effect.wantsLayer = true
            effect.layer?.cornerRadius = HUDMetrics.cornerRadius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            backgroundView = effect
        }

        super.init(frame: frameRect)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HUDView is created in code only")
    }

    override var isOpaque: Bool { false }

    private func setUp() {
        addSubview(backgroundView)

        overlay.wantsLayer = true

        if #available(macOS 26.0, *), let glass = backgroundView as? NSGlassEffectView {
            // The content lives *inside* the glass, so it picks up the
            // material's rendering rather than floating above it.
            glass.contentView = overlay
        } else {
            addSubview(overlay)
        }

        trackLayer.cornerRadius = HUDMetrics.barCornerRadius
        overlay.layer?.addSublayer(trackLayer)

        fillLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        fillLayer.cornerRadius = HUDMetrics.barCornerRadius
        overlay.layer?.addSublayer(fillLayer)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.imageAlignment = .alignCenter
        iconView.imageFrameStyle = .none
        iconView.setAccessibilityElement(false)
        overlay.addSubview(iconView)

        setAccessibilityElement(false)
        updateContentsScale()
    }

    // MARK: - Configuration

    func configure(edge: EdgeAction, level: Double, muted: Bool, appearance: AppearanceMode, animated: Bool) {
        applyAppearance(appearance)

        showsLevel = true
        self.level = level
        isMuted = muted

        let color = resolvedContentColor()
        applyColors(color: color)
        applyIcon(
            name: muted ? "speaker.slash.fill" : edge.symbolName,
            pointSize: HUDMetrics.levelSymbolPointSize,
            color: color
        )

        withoutAnimations {
            trackLayer.isHidden = false
            fillLayer.isHidden = false
        }

        applyFill(animated: animated)
        needsLayout = true
    }

    func configure(media symbol: MediaSymbol, appearance: AppearanceMode) {
        applyAppearance(appearance)

        showsLevel = false

        let color = resolvedContentColor()
        applyColors(color: color)
        applyIcon(
            name: symbol.hudSymbolName,
            pointSize: HUDMetrics.mediaSymbolPointSize,
            color: color
        )

        withoutAnimations {
            trackLayer.isHidden = true
            fillLayer.isHidden = true
        }

        needsLayout = true
    }

    private func applyAppearance(_ mode: AppearanceMode) {
        let appearance: NSAppearance?
        switch mode {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }
        // Set on the background so the glass/effect renders in the right
        // scheme; the content colours are resolved against it below.
        backgroundView.appearance = appearance
    }

    // MARK: - Layout

    /// Level bar in view coordinates: 48 ... 196 at the default 210 pt width,
    /// vertically centred in the 60 pt pill.
    var barRect: CGRect {
        let x = HUDMetrics.barOriginX
        let width = max(0, bounds.width - x - HUDMetrics.contentInset)
        return CGRect(
            x: x,
            y: (bounds.height - HUDMetrics.barHeight) / 2,
            width: width,
            height: HUDMetrics.barHeight
        )
    }

    /// Level HUD: the square icon box on the leading edge.
    /// Media HUD: the wide glyph box, centred in the pill.
    var iconFrame: CGRect {
        if showsLevel {
            return CGRect(
                x: HUDMetrics.contentInset,
                y: (bounds.height - HUDMetrics.iconBoxHeight) / 2,
                width: HUDMetrics.iconBoxWidth,
                height: HUDMetrics.iconBoxHeight
            )
        }
        let width = HUDMetrics.mediaIconWidth
        let height = HUDMetrics.mediaIconHeight
        return CGRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
    }

    override func layout() {
        super.layout()

        backgroundView.frame = bounds
        overlay.frame = bounds

        withoutAnimations {
            let bar = barRect
            trackLayer.frame = bar
            fillLayer.position = CGPoint(x: bar.minX, y: bar.midY)
            fillLayer.bounds = CGRect(x: 0, y: 0, width: fillWidth, height: HUDMetrics.barHeight)
            // A zero-width rounded layer still paints an anti-aliased bowtie,
            // so hide it outright instead.
            fillLayer.isHidden = !showsLevel || fillWidth <= 0

            iconView.frame = iconFrame
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? 2
        trackLayer.contentsScale = scale
        fillLayer.contentsScale = scale
    }

    // MARK: - Level bar

    /// Width of the fill in points. Zero at 0 %, the full bar at 100 %, and
    /// never thinner than one rounded cap once the level is visible.
    var fillWidth: CGFloat {
        guard showsLevel else { return 0 }
        let clamped = level.isFinite ? min(max(level, 0), 1) : 0
        guard clamped > HUDMetrics.minimumVisibleLevel else { return 0 }
        let width = barRect.width * clamped
        guard width > 0 else { return 0 }
        return max(HUDMetrics.barHeight, width)
    }

    private func applyFill(animated: Bool) {
        guard showsLevel else { return }

        let target = fillWidth
        let newBounds = CGRect(x: 0, y: 0, width: target, height: HUDMetrics.barHeight)
        let current = fillLayer.presentation()?.bounds.size.width ?? fillLayer.bounds.size.width

        fillLayer.removeAnimation(forKey: "fillWidth")
        withoutAnimations {
            fillLayer.bounds = newBounds
        }

        guard animated,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              abs(current - target) > 0.5
        else { return }

        let animation = CABasicAnimation(keyPath: "bounds")
        animation.fromValue = NSValue(rect: CGRect(x: 0, y: 0, width: current, height: HUDMetrics.barHeight))
        animation.toValue = NSValue(rect: newBounds)
        animation.duration = HUDMetrics.fillAnimationDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.isRemovedOnCompletion = true
        fillLayer.add(animation, forKey: "fillWidth")
    }

    // MARK: - Icon

    private func applyIcon(name: String, pointSize: CGFloat, color: NSColor) {
        iconSymbolName = name

        let key = "\(name)|\(pointSize)|\(color.description)"
        guard key != iconKey else { return }
        iconKey = key

        iconView.contentTintColor = color

        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            iconView.image = nil
            return
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        iconView.image = base.withSymbolConfiguration(configuration) ?? base
    }

    // MARK: - Colours

    /// `labelColor` resolved against the background's appearance, so the
    /// content is white on the dark HUD and near-black on the light one.
    ///
    /// The colour is materialised to a `CGColor` *inside* the appearance so it
    /// stops being a dynamic colour: otherwise a later `.cgColor` lookup would
    /// resolve it against the app's appearance instead of the HUD's.
    private func resolvedContentColor() -> NSColor {
        var resolved = NSColor.labelColor
        backgroundView.effectiveAppearance.performAsCurrentDrawingAppearance {
            let cgColor = NSColor.labelColor.cgColor
            resolved = NSColor(cgColor: cgColor) ?? NSColor.labelColor
        }
        return resolved
    }

    private func applyColors(color: NSColor) {
        guard color != currentContentColor || isMuted != currentMuted else { return }
        currentContentColor = color
        currentMuted = isMuted

        let track = color.withAlphaComponent(0.18)
        let fill = isMuted ? color.withAlphaComponent(0.40) : color

        withoutAnimations {
            trackLayer.backgroundColor = track.cgColor
            fillLayer.backgroundColor = fill.cgColor
        }
    }

    // MARK: - Snapshots

    /// Swaps the material for a flat opaque plate so a headless render shows
    /// the HUD's real content instead of an empty blur. Test support only.
    func replaceBackgroundForSnapshot(color: NSColor) {
        if #available(macOS 26.0, *), let glass = backgroundView as? NSGlassEffectView {
            glass.contentView = nil
        }
        backgroundView.removeFromSuperview()

        if overlay.superview !== self {
            addSubview(overlay)
        }
        overlay.frame = bounds

        let plate = NSView(frame: bounds)
        plate.wantsLayer = true
        plate.layer?.backgroundColor = color.cgColor
        plate.layer?.cornerRadius = HUDMetrics.cornerRadius
        plate.layer?.cornerCurve = .continuous
        plate.layer?.masksToBounds = true
        addSubview(plate, positioned: .below, relativeTo: overlay)
    }

    // MARK: - Helpers

    private func withoutAnimations(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}

extension MediaSymbol {
    var hudSymbolName: String {
        switch self {
        case .playPause: return "playpause.fill"
        case .next: return "forward.fill"
        case .previous: return "backward.fill"
        }
    }
}

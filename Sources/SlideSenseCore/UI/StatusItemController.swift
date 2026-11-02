import AppKit
import Foundation

public protocol StatusItemDataSource: AnyObject {
    var volumeLevel: Double { get }
    var brightnessLevel: Double { get }
    var isMuted: Bool { get }
    func requestSettings()
    func requestQuit()
}

/// The menu bar item and its menu.
///
/// The menu is deliberately minimal — two live readouts, an enable switch,
/// Settings and Quit — and is built exactly once. `refresh()` only rewrites
/// item titles and state, so it stays cheap when called every second and
/// keeps working while the menu is open.
public final class StatusItemController {
    private let store: SettingsStore
    private weak var dataSource: StatusItemDataSource?

    private var statusItem: NSStatusItem?
    private let menuDelegate = PlainTextMenuDelegate()

    // Menu items whose contents are updated in place by `refresh()`.
    private var volumeItem: NSMenuItem?
    private var brightnessItem: NSMenuItem?
    private var enabledItem: NSMenuItem?

    /// The installed menu, exposed for tests and snapshot tooling.
    var menu: NSMenu? { statusItem?.menu }

    /// Called just before the menu is displayed, so the app can refresh the
    /// live readouts without a timer running in the background.
    public var willOpen: (() -> Void)? {
        get { menuDelegate.onWillOpen }
        set { menuDelegate.onWillOpen = newValue }
    }

    /// The state the current button image was drawn from; the image is only
    /// redrawn when this changes.
    private(set) var iconState: StatusItemIconState?

    /// The status item's button, exposed for tests and snapshot tooling.
    var button: NSStatusBarButton? { statusItem?.button }

    // MARK: - Lifecycle

    public init(store: SettingsStore, dataSource: StatusItemDataSource) {
        self.store = store
        self.dataSource = dataSource

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityLabel("SlideSense")
        statusItem = item

        buildMenu()
        refresh()
    }

    // MARK: - Refresh

    /// Cheap update called when a level or setting changes and before the menu
    /// opens. Never rebuilds the menu, so an open menu keeps its highlight.
    public func refresh() {
        refreshIcon()
        updateReadouts()
        enabledItem?.state = store.settings.enabled ? .on : .off
    }

    /// Updates only the menu bar glyph. Cheap enough to call on every frame
    /// of a slide: the image is redrawn only when a bar gains or loses a pixel.
    public func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let settings = store.settings

        let state = StatusItemIconState(
            leftLevel: displayedLevel(for: settings.leftEdge),
            rightLevel: displayedLevel(for: settings.rightEdge),
            enabled: settings.enabled
        )
        if state != iconState || button.image == nil {
            button.image = StatusItemIcon.image(for: state)
            iconState = state
        }

        button.toolTip = settings.enabled ? "SlideSense" : "SlideSense (Off)"
        button.setAccessibilityValue("\(volumeText()), Brightness \(percent(brightnessLevel()))")
    }

    // MARK: - Levels

    private func volumeLevel() -> Double { clamped(dataSource?.volumeLevel ?? 0) }
    private func brightnessLevel() -> Double { clamped(dataSource?.brightnessLevel ?? 0) }
    private func isMuted() -> Bool { dataSource?.isMuted ?? false }

    /// The level a bar shows. A muted output reads as empty, matching the HUD.
    private func displayedLevel(for action: EdgeAction) -> Double {
        switch action {
        case .volume: return isMuted() ? 0 : volumeLevel()
        case .brightness: return brightnessLevel()
        }
    }

    private func volumeText() -> String {
        isMuted() ? "Volume Muted" : "Volume \(percent(volumeLevel()))"
    }

    // MARK: - Readouts

    private func updateReadouts() {
        volumeItem?.attributedTitle = readout(
            label: "Volume",
            value: isMuted() ? "Muted" : percent(volumeLevel())
        )
        brightnessItem?.attributedTitle = readout(
            label: "Brightness",
            value: percent(brightnessLevel())
        )
    }

    /// A menu row with the label on the left and the value right-aligned,
    /// like the informational rows in Apple's own menu extras.
    private func readout(label: String, value: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 190, options: [:])]

        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        let title = NSMutableAttributedString(
            string: "\(label)\t\(value)",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )
        if let range = title.string.range(of: value, options: .backwards) {
            title.addAttribute(
                .foregroundColor,
                value: NSColor.secondaryLabelColor,
                range: NSRange(range, in: title.string)
            )
        }
        return title
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", clamped(value) * 100)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    // MARK: - Menu construction

    /// Builds the menu exactly once. Plain text only — no images, no bullets.
    private func buildMenu() {
        guard let statusItem else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = menuDelegate

        let volume = readoutItem()
        menu.addItem(volume)

        let brightness = readoutItem()
        menu.addItem(brightness)

        menu.addItem(.separator())

        let enabled = NSMenuItem(
            title: "Enabled",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enabled.target = self
        menu.addItem(enabled)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = .command
        settings.target = self
        // macOS attaches a gear symbol to items titled like Settings; the
        // menu is text-only by design.
        settings.image = nil
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit SlideSense",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = .command
        quit.target = self
        menu.addItem(quit)

        volumeItem = volume
        brightnessItem = brightness
        enabledItem = enabled
        statusItem.menu = menu

        // AppKit decorates the "Settings…" item with a gear symbol as soon as
        // the menu is installed; clear every image so the menu is text-only.
        for item in menu.items where item.image != nil {
            item.image = nil
        }
    }

    /// A disabled, non-highlighting item used for the live level readouts.
    private func readoutItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.action = nil
        item.target = nil
        return item
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        store.settings.enabled.toggle()
        refresh()
    }

    @objc private func openSettings() {
        dataSource?.requestSettings()
    }

    @objc private func quit() {
        dataSource?.requestQuit()
    }
}

// MARK: - Menu delegate

/// Strips the SF Symbol gear that macOS attaches to items with standard
/// titles such as "Settings…", keeping the menu plain text.
private final class PlainTextMenuDelegate: NSObject, NSMenuDelegate {
    var onWillOpen: (() -> Void)?

    func menuWillOpen(_ menu: NSMenu) {
        onWillOpen?()
        for item in menu.items where item.image != nil {
            item.image = nil
        }
    }
}

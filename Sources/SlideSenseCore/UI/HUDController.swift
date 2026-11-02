import AppKit
import Foundation

public enum MediaSymbol: CaseIterable, Sendable {
    case playPause
    case next
    case previous
}

/// Borderless, non-activating panel that hosts the HUD. It can never become key
/// or main, so showing it never pulls focus away from the app in front.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// On-screen display shown while a level is being changed.
///
/// Implemented as a single reused non-activating floating panel so it never
/// steals focus and disappears on its own. All entry points hop to the main
/// thread if needed; UI updates are cheap because only layer properties change.
public final class HUDController {

    private enum Layout {
        static let marginFromScreenEdge: CGFloat = 16
        static let fadeInDuration: TimeInterval = 0.15
        static let fadeOutDuration: TimeInterval = 0.20
        static let visibleDuration: TimeInterval = 1.0
    }

    private let store: SettingsStore

    private var panel: HUDPanel?
    private var hudView: HUDView?
    private var hideWorkItem: DispatchWorkItem?
    /// Incremented whenever visibility is requested or cancelled, so a stale
    /// fade-out completion can never order out a panel that was just re-shown.
    private var presentationToken: UInt = 0

    public init(store: SettingsStore) {
        self.store = store
    }

    deinit {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        if Thread.isMainThread, let panel {
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    // MARK: - Public API

    public func show(edge: EdgeAction, level: Double, muted: Bool) {
        onMain { [weak self] in
            guard let self else { return }
            self.presentLevel(edge: edge, level: level, muted: muted)
        }
    }

    public func showMedia(_ symbol: MediaSymbol) {
        onMain { [weak self] in
            guard let self else { return }
            self.presentMedia(symbol)
        }
    }

    public func dismiss() {
        onMain { [weak self] in
            self?.hidePanel(immediately: true)
        }
    }

    // MARK: - Presentation

    private func presentLevel(edge: EdgeAction, level: Double, muted: Bool) {
        guard store.settings.showHUD else {
            hidePanel(immediately: true)
            return
        }

        let panel = ensurePanel()
        applyAppearance(to: panel)

        let isAlreadyVisible = panel.isVisible
        hudView?.configure(
            edge: edge,
            level: level,
            muted: muted,
            appearance: store.settings.appearance,
            animated: isAlreadyVisible
        )
        hudView?.layoutSubtreeIfNeeded()

        position(panel)
        fadeIn(panel)
        scheduleAutoHide()
    }

    private func presentMedia(_ symbol: MediaSymbol) {
        guard store.settings.showHUD else {
            hidePanel(immediately: true)
            return
        }

        let panel = ensurePanel()
        applyAppearance(to: panel)

        hudView?.configure(media: symbol, appearance: store.settings.appearance)
        hudView?.layoutSubtreeIfNeeded()

        position(panel)
        fadeIn(panel)
        scheduleAutoHide()
    }

    private func fadeIn(_ panel: NSPanel) {
        presentationToken &+= 1

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }

        // Already fully visible: nothing to animate. Keeps a stream of slide
        // updates from restarting the fade on every frame.
        guard panel.alphaValue < 1 else { return }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.fadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func scheduleAutoHide() {
        hideWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hideWorkItem = nil
            self.hidePanel(immediately: false)
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.visibleDuration, execute: item)
    }

    private func hidePanel(immediately: Bool) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        presentationToken &+= 1

        guard let panel else { return }

        guard !immediately, panel.isVisible else {
            panel.orderOut(nil)
            panel.alphaValue = 0
            return
        }

        let token = presentationToken

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            guard let self, let panel, self.presentationToken == token else { return }
            panel.orderOut(nil)
            panel.alphaValue = 0
        }
    }

    // MARK: - Panel

    private func ensurePanel() -> HUDPanel {
        if let panel {
            return panel
        }

        let size = HUDView.preferredSize
        let panel = HUDPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        panel.title = "SlideSense HUD"

        let view = HUDView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = view

        self.panel = panel
        self.hudView = view
        return panel
    }

    private func applyAppearance(to panel: NSPanel) {
        switch store.settings.appearance {
        case .system:
            panel.appearance = nil
        case .light:
            panel.appearance = NSAppearance(named: .aqua)
        case .dark:
            panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Top-right of whichever screen currently contains the pointer. Called on
    /// every show so the HUD follows the pointer between monitors.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            return
        }

        let visible = screen.visibleFrame
        let size = HUDView.preferredSize
        let target = NSRect(
            x: visible.maxX - size.width - Layout.marginFromScreenEdge,
            y: visible.maxY - size.height - Layout.marginFromScreenEdge,
            width: size.width,
            height: size.height
        )

        guard panel.frame != target else { return }
        panel.setFrame(target, display: false)
    }

    // MARK: - Threading

    private func onMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread {
            body()
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }
}

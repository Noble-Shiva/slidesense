import AppKit
import XCTest
@testable import SlideSenseCore

final class StatusItemTests: XCTestCase {
    private final class StubSource: StatusItemDataSource {
        var volumeLevel: Double = 0.81
        var brightnessLevel: Double = 0.69
        var isMuted = false

        private(set) var settingsRequests = 0
        private(set) var quitRequests = 0

        func requestSettings() { settingsRequests += 1 }
        func requestQuit() { quitRequests += 1 }
    }

    private var store: SettingsStore!
    private var source: StubSource!

    override func setUp() {
        super.setUp()
        let suiteName = "io.github.slidesense.statusitem.\(UUID().uuidString)"
        store = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        source = StubSource()
    }

    private func makeController() -> StatusItemController {
        StatusItemController(store: store, dataSource: source)
    }

    private func items(_ controller: StatusItemController) -> [NSMenuItem] {
        controller.menu?.items ?? []
    }

    // MARK: - Structure

    func testMenuIsMinimalAndOrdered() {
        let controller = makeController()
        let items = items(controller)

        XCTAssertEqual(items.count, 7)
        XCTAssertTrue(items[0].title.hasPrefix("Volume"))
        XCTAssertTrue(items[1].title.hasPrefix("Brightness"))
        XCTAssertTrue(items[2].isSeparatorItem)
        XCTAssertEqual(items[3].title, "Enabled")
        XCTAssertEqual(items[4].title, "Settings…")
        XCTAssertTrue(items[5].isSeparatorItem)
        XCTAssertEqual(items[6].title, "Quit SlideSense")
    }

    func testReadoutItemsAreDisabledAndPlain() {
        let controller = makeController()
        let menuItems = items(controller)
        let volume = menuItems[0]
        let brightness = menuItems[1]

        for item in [volume, brightness] {
            XCTAssertFalse(item.isEnabled)
            XCTAssertNil(item.image)
            XCTAssertNil(item.action)
            let text = item.attributedTitle?.string ?? ""
            XCTAssertFalse(text.isEmpty)
        }
        XCTAssertTrue(volume.attributedTitle?.string.contains("Volume") ?? false)
        XCTAssertTrue(volume.attributedTitle?.string.contains("81%") ?? false)
        XCTAssertTrue(brightness.attributedTitle?.string.contains("69%") ?? false)
    }

    func testMenuHasNoImagesAnywhere() {
        let controller = makeController()
        for item in items(controller) {
            XCTAssertNil(item.image, "\(item.title) should not carry an image")
        }
    }

    func testKeyEquivalents() {
        let controller = makeController()
        let menuItems = items(controller)
        let settings = menuItems.first { $0.title == "Settings…" }
        let quit = menuItems.first { $0.title == "Quit SlideSense" }

        XCTAssertEqual(settings?.keyEquivalent, ",")
        XCTAssertEqual(settings?.keyEquivalentModifierMask, .command)
        XCTAssertEqual(quit?.keyEquivalent, "q")
        XCTAssertEqual(quit?.keyEquivalentModifierMask, .command)
    }

    // MARK: - State

    func testEnabledCheckmarkFollowsSettings() {
        let controller = makeController()
        let enabled = items(controller).first { $0.title == "Enabled" }
        XCTAssertEqual(enabled?.state, .on)

        store.settings.enabled = false
        controller.refresh()
        XCTAssertEqual(enabled?.state, .off)

        store.settings.enabled = true
        controller.refresh()
        XCTAssertEqual(enabled?.state, .on)
    }

    func testMutedReadout() {
        let controller = makeController()
        source.isMuted = true
        controller.refresh()
        let volume = items(controller)[0]
        XCTAssertTrue(volume.attributedTitle?.string.contains("Muted") ?? false)
    }

    func testReadoutsClampOutOfRangeValues() {
        let controller = makeController()
        source.volumeLevel = 1.4
        source.brightnessLevel = -0.3
        controller.refresh()

        let menuItems = items(controller)
        XCTAssertTrue(menuItems[0].attributedTitle?.string.contains("100%") ?? false)
        XCTAssertTrue(menuItems[1].attributedTitle?.string.contains("0%") ?? false)
    }

    func testRefreshKeepsTheSameMenuObject() {
        let controller = makeController()
        let first = controller.menu
        controller.refresh()
        XCTAssertTrue(controller.menu === first, "refresh must not rebuild the menu")
    }

    // MARK: - Live icon: metrics

    func testBarHeightSpansMinimumToMaximum() {
        typealias M = StatusItemIconMetrics
        XCTAssertEqual(M.barHeight(for: 0), M.minimumBarHeight)
        XCTAssertEqual(M.barHeight(for: 1), M.maximumBarHeight)
        // 1.5 + 0.5 × 7.5 = 5.25, which snaps to the nearest half point.
        XCTAssertEqual(M.barHeight(for: 0.5), 5.5)
    }

    func testBarHeightClampsAndIgnoresNonFiniteInput() {
        typealias M = StatusItemIconMetrics
        XCTAssertEqual(M.barHeight(for: -0.4), M.minimumBarHeight)
        XCTAssertEqual(M.barHeight(for: 3), M.maximumBarHeight)
        XCTAssertEqual(M.barHeight(for: .nan), M.minimumBarHeight)
    }

    func testBarHeightSnapsToWholePixelsAndNeverShrinksAsLevelRises() {
        typealias M = StatusItemIconMetrics
        var previous = M.barHeight(for: 0)
        for step in 0...200 {
            let height = M.barHeight(for: Double(step) / 200)
            let pixels = height / M.heightQuantum
            XCTAssertEqual(pixels, pixels.rounded(), accuracy: 0.0001, "height \(height) is not pixel-aligned")
            XCTAssertGreaterThanOrEqual(height, previous)
            previous = height
        }
    }

    func testBarsStayInsideTheOutline() {
        typealias M = StatusItemIconMetrics
        let inner = M.outlineRect.insetBy(dx: M.outlineLineWidth / 2, dy: M.outlineLineWidth / 2)
        for x in [M.leftBarX, M.rightBarX] {
            let tallest = NSRect(x: x, y: M.barBottom, width: M.barWidth, height: M.maximumBarHeight)
            XCTAssertTrue(inner.contains(tallest), "\(tallest) spills outside \(inner)")
        }
    }

    // MARK: - Live icon: controller

    func testIconBarsFollowTheDefaultEdges() {
        source.brightnessLevel = 0.2
        source.volumeLevel = 0.9
        let controller = makeController()

        XCTAssertEqual(controller.iconState?.leftBarHeight, StatusItemIconMetrics.barHeight(for: 0.2))
        XCTAssertEqual(controller.iconState?.rightBarHeight, StatusItemIconMetrics.barHeight(for: 0.9))
        XCTAssertEqual(controller.iconState?.enabled, true)
        XCTAssertTrue(controller.button?.image?.isTemplate ?? false)
    }

    func testSwappedSidesSwapTheBars() {
        source.brightnessLevel = 0.2
        source.volumeLevel = 0.9
        store.settings.swapped = true
        let controller = makeController()

        XCTAssertEqual(controller.iconState?.leftBarHeight, StatusItemIconMetrics.barHeight(for: 0.9))
        XCTAssertEqual(controller.iconState?.rightBarHeight, StatusItemIconMetrics.barHeight(for: 0.2))
    }

    func testMutedVolumeShowsAnEmptyBar() {
        source.isMuted = true
        let controller = makeController()
        XCTAssertEqual(controller.iconState?.rightBarHeight, StatusItemIconMetrics.minimumBarHeight)
    }

    func testDisabledStateIsReflectedInTheIcon() {
        let controller = makeController()
        store.settings.enabled = false
        controller.refreshIcon()
        XCTAssertEqual(controller.iconState?.enabled, false)
        XCTAssertEqual(controller.button?.toolTip, "SlideSense (Off)")
    }

    func testIconRedrawsOnlyWhenABarChangesByAPixel() {
        source.volumeLevel = 0.5
        let controller = makeController()
        let first = controller.button?.image

        // Far below one pixel of bar height: same image object.
        source.volumeLevel = 0.501
        controller.refreshIcon()
        XCTAssertTrue(controller.button?.image === first)

        // A full step: a new image.
        source.volumeLevel = 0.75
        controller.refreshIcon()
        XCTAssertFalse(controller.button?.image === first)
    }

    func testButtonAccessibilityValueReadsBothLevels() {
        let controller = makeController()
        XCTAssertEqual(controller.button?.accessibilityValue() as? String, "Volume 81%, Brightness 69%")

        source.isMuted = true
        controller.refreshIcon()
        XCTAssertEqual(controller.button?.accessibilityValue() as? String, "Volume Muted, Brightness 69%")
    }

    // MARK: - Live icon: snapshots

    /// Set `SLIDESENSE_SNAPSHOT_DIR` to write the menu bar glyph at several
    /// levels, tinted as the light and dark menu bars tint template images.
    func testSnapshotRendersIconStates() throws {
        guard let directory = ProcessInfo.processInfo.environment["SLIDESENSE_SNAPSHOT_DIR"],
              !directory.isEmpty
        else {
            throw XCTSkip("SLIDESENSE_SNAPSHOT_DIR not set; skipping status icon snapshots")
        }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let states: [(String, StatusItemIconState)] = [
            ("0-0", .init(leftLevel: 0, rightLevel: 0, enabled: true)),
            ("37-38", .init(leftLevel: 0.37, rightLevel: 0.38, enabled: true)),
            ("50-100", .init(leftLevel: 0.5, rightLevel: 1, enabled: true)),
            ("100-100", .init(leftLevel: 1, rightLevel: 1, enabled: true)),
            ("69-81-off", .init(leftLevel: 0.69, rightLevel: 0.81, enabled: false))
        ]
        let appearances: [(String, NSColor, NSColor)] = [
            ("light", NSColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1), .black),
            ("dark", NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1), .white)
        ]

        for (name, state) in states {
            for (appearanceName, backdrop, tint) in appearances {
                let data = try XCTUnwrap(renderIcon(StatusItemIcon.image(for: state), backdrop: backdrop, tint: tint))
                let file = folder.appendingPathComponent("status-icon-\(name)-\(appearanceName).png")
                try data.write(to: file)
                print("snapshot: \(file.path)")
            }
        }
    }

    /// Renders a template image at 2× over a menu-bar-coloured backdrop.
    private func renderIcon(_ icon: NSImage, backdrop: NSColor, tint: NSColor) -> Data? {
        let size = icon.size
        let tinted = NSImage(size: size, flipped: false) { rect in
            icon.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        backdrop.setFill()
        NSRect(origin: .zero, size: size).fill()
        tinted.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Actions

    func testSettingsAndQuitRouteToTheDataSource() {
        let controller = makeController()
        let menuItems = items(controller)

        let settings = menuItems.first { $0.title == "Settings…" }
        XCTAssertNotNil(settings?.target)
        _ = settings?.target?.perform(settings?.action, with: settings)
        XCTAssertEqual(source.settingsRequests, 1)

        let quit = menuItems.first { $0.title == "Quit SlideSense" }
        XCTAssertNotNil(quit?.target)
        _ = quit?.target?.perform(quit?.action, with: quit)
        XCTAssertEqual(source.quitRequests, 1)
    }
}

import AppKit
import XCTest
@testable import SlideSenseCore

/// Geometry and state tests for the HUD, plus an opt-in snapshot harness.
///
/// Set `SLIDESENSE_SNAPSHOT_DIR` to write 2× PNGs of every HUD state in both
/// appearances:
///
///     SLIDESENSE_SNAPSHOT_DIR=/tmp/hudshots swift test --filter HUDLayoutTests
final class HUDLayoutTests: XCTestCase {

    private let size = NSSize(width: HUDMetrics.panelWidth, height: HUDMetrics.panelHeight)

    // MARK: - Helpers

    /// A HUD laid out at its real size on a 2× backing scale. No window is
    /// created, so `HUDView` falls back to scale 2 deterministically.
    private func makeHUD() -> HUDView {
        let view = HUDView(frame: NSRect(origin: .zero, size: size))
        view.layoutSubtreeIfNeeded()
        view.layout()
        return view
    }

    @discardableResult
    private func laidOut(_ view: HUDView) -> HUDView {
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        view.layout()
        return view
    }

    // MARK: - Panel size

    func testPanelSizeConstant() {
        XCTAssertEqual(HUDView.preferredSize.width, 210)
        XCTAssertEqual(HUDView.preferredSize.height, 60)
        XCTAssertEqual(HUDMetrics.panelWidth, 210)
        XCTAssertEqual(HUDMetrics.panelHeight, 60)
    }

    func testRetinaContentsScale() {
        let hud = makeHUD()
        XCTAssertEqual(hud.trackLayer.contentsScale, 2, accuracy: 0.0001)
        XCTAssertEqual(hud.fillLayer.contentsScale, 2, accuracy: 0.0001)
    }

    // MARK: - Bar geometry

    func testBarRectIsExact() {
        let hud = laidOut(makeHUD())
        hud.configure(edge: .volume, level: 0.5, muted: false, appearance: .dark, animated: false)
        laidOut(hud)

        let expected = CGRect(x: 48, y: 26, width: 148, height: 8)
        XCTAssertEqual(hud.barRect, expected)
        XCTAssertEqual(hud.trackLayer.frame, expected)
        XCTAssertEqual(hud.fillLayer.position, CGPoint(x: 48, y: 30))
    }

    func testBarLayersAreEightPointsTallWithFourPointRadius() {
        let hud = laidOut(makeHUD())
        hud.configure(edge: .volume, level: 0.5, muted: false, appearance: .dark, animated: false)
        laidOut(hud)

        XCTAssertEqual(hud.trackLayer.bounds.height, 8)
        XCTAssertEqual(hud.trackLayer.cornerRadius, 4)
        XCTAssertEqual(hud.fillLayer.bounds.height, 8)
        XCTAssertEqual(hud.fillLayer.cornerRadius, 4)
    }

    func testFillWidths() {
        let hud = laidOut(makeHUD())

        let cases: [(level: Double, expected: CGFloat)] = [
            (0.0, 0),
            (0.5, 74),
            (1.0, 148)
        ]

        for testCase in cases {
            hud.configure(
                edge: .volume,
                level: testCase.level,
                muted: false,
                appearance: .dark,
                animated: false
            )
            laidOut(hud)
            XCTAssertEqual(hud.fillWidth, testCase.expected, accuracy: 0.0001, "level \(testCase.level)")
            XCTAssertEqual(
                hud.fillLayer.bounds.width,
                testCase.expected,
                accuracy: 0.0001,
                "layer width at level \(testCase.level)"
            )
        }
    }

    func testTinyLevelsSnapToZeroOrTheMinimumCap() {
        let hud = laidOut(makeHUD())

        hud.configure(edge: .volume, level: 0.001, muted: false, appearance: .dark, animated: false)
        laidOut(hud)
        XCTAssertEqual(hud.fillWidth, 0, "0.001 is below the visibility threshold")
        XCTAssertEqual(hud.fillLayer.bounds.width, 0)

        hud.configure(edge: .volume, level: 0.01, muted: false, appearance: .dark, animated: false)
        laidOut(hud)
        XCTAssertGreaterThanOrEqual(hud.fillWidth, HUDMetrics.barHeight)
        XCTAssertEqual(hud.fillWidth, HUDMetrics.barHeight, "1 % renders as one rounded cap")
    }

    // MARK: - Icon geometry

    func testLevelIconFrame() {
        let hud = laidOut(makeHUD())
        hud.configure(edge: .volume, level: 0.5, muted: false, appearance: .dark, animated: false)
        laidOut(hud)

        let expected = CGRect(x: 14, y: 19, width: 22, height: 22)
        XCTAssertEqual(hud.iconFrame, expected)
        XCTAssertEqual(hud.iconView.frame, expected)
    }

    func testMediaIconFrameIsCentred() {
        let hud = laidOut(makeHUD())
        hud.configure(media: .playPause, appearance: .dark)
        laidOut(hud)

        let expected = CGRect(x: 85, y: 15, width: 40, height: 30)
        XCTAssertEqual(hud.iconFrame, expected)
        XCTAssertEqual(hud.iconView.frame, expected)
        XCTAssertTrue(hud.trackLayer.isHidden)
        XCTAssertTrue(hud.fillLayer.isHidden)
    }

    // MARK: - Muted state

    func testMutedStateUsesSlashSymbolAndDimmedFill() {
        let hud = laidOut(makeHUD())

        hud.configure(edge: .volume, level: 0.6, muted: true, appearance: .dark, animated: false)
        laidOut(hud)

        XCTAssertEqual(hud.iconSymbolName, "speaker.slash.fill")
        XCTAssertNotNil(hud.fillLayer.backgroundColor)
        XCTAssertEqual(hud.fillLayer.backgroundColor?.alpha ?? -1, 0.40, accuracy: 0.001)
        XCTAssertEqual(hud.fillWidth, 148 * 0.6, accuracy: 0.5)

        hud.configure(edge: .volume, level: 0.6, muted: false, appearance: .dark, animated: false)
        laidOut(hud)

        XCTAssertEqual(hud.iconSymbolName, "speaker.wave.2.fill")
        XCTAssertGreaterThan(hud.fillLayer.backgroundColor?.alpha ?? -1, 0.40)
    }

    // MARK: - Symbols

    func testEveryMediaSymbolIsAValidSFSymbol() {
        for symbol in MediaSymbol.allCases {
            let name = symbol.hudSymbolName
            XCTAssertNotNil(
                NSImage(systemSymbolName: name, accessibilityDescription: nil),
                "\(name) is not a valid SF Symbol"
            )
        }
    }

    func testLevelSymbolsAreValidSFSymbols() {
        for edge in EdgeAction.allCases {
            XCTAssertNotNil(
                NSImage(systemSymbolName: edge.symbolName, accessibilityDescription: nil),
                "\(edge.symbolName) is not a valid SF Symbol"
            )
        }
        XCTAssertNotNil(NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: nil))
    }

    // MARK: - Snapshots

    private enum SnapshotState {
        case level(EdgeAction, Double, Bool)
        case media(MediaSymbol)

        var name: String {
            switch self {
            case let .level(edge, level, muted):
                if muted {
                    return "muted-\(Int((level * 100).rounded()))"
                }
                return "\(edge.rawValue)-\(Int((level * 100).rounded()))"
            case let .media(symbol):
                switch symbol {
                case .playPause: return "media-playpause"
                case .next: return "media-next"
                case .previous: return "media-previous"
                }
            }
        }
    }

    private static let snapshotStates: [SnapshotState] = [
        .level(.volume, 0.0, false),
        .level(.volume, 0.01, false),
        .level(.volume, 0.5, false),
        .level(.volume, 1.0, false),
        .level(.volume, 0.6, true),
        .level(.brightness, 0.86, false),
        .media(.playPause),
        .media(.next),
        .media(.previous)
    ]

    func testSnapshotRendersEveryState() throws {
        guard let directory = ProcessInfo.processInfo.environment["SLIDESENSE_SNAPSHOT_DIR"],
              !directory.isEmpty
        else {
            throw XCTSkip("SLIDESENSE_SNAPSHOT_DIR not set; skipping HUD snapshots")
        }

        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let appearances: [(AppearanceMode, String, NSColor)] = [
            (.light, "light", NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1)),
            (.dark, "dark", NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1))
        ]

        for state in Self.snapshotStates {
            for (appearance, appearanceName, backdrop) in appearances {
                let hud = HUDView(frame: NSRect(origin: .zero, size: size))

                switch state {
                case let .level(edge, level, muted):
                    hud.configure(
                        edge: edge,
                        level: level,
                        muted: muted,
                        appearance: appearance,
                        animated: false
                    )
                case let .media(symbol):
                    hud.configure(media: symbol, appearance: appearance)
                }

                hud.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
                hud.replaceBackgroundForSnapshot(color: backdrop)
                laidOut(hud)

                let data = try XCTUnwrap(renderPNG(hud), "could not render \(state.name)-\(appearanceName)")
                let file = folder.appendingPathComponent("hud-\(state.name)-\(appearanceName).png")
                try data.write(to: file)
                print("snapshot: \(file.path)")
            }
        }
    }

    /// Renders the view hierarchy at 2× into PNG data.
    private func renderPNG(_ view: NSView) -> Data? {
        let scale: CGFloat = 2
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((bounds.width * scale).rounded()),
            pixelsHigh: Int((bounds.height * scale).rounded()),
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
        rep.size = bounds.size

        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        view.cacheDisplay(in: bounds, to: rep)

        return rep.representation(using: .png, properties: [:])
    }
}

#!/usr/bin/env swift
//
// Draws the SlideSense app icon and writes Resources/AppIcon.icns.
//
//   swift scripts/make-icon.swift
//
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")
let icns = resources.appendingPathComponent("AppIcon.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size
    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225

    // Background: a deep graphite rounded square with a soft vertical fade.
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()

    let colours = [
        NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1).cgColor,
        NSColor(srgbRed: 0.07, green: 0.07, blue: 0.09, alpha: 1).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.minY),
            options: []
        )
    }

    // Inner trackpad outline.
    let padInset = s * 0.20
    let pad = CGRect(
        x: padInset,
        y: s * 0.26,
        width: s - padInset * 2,
        height: s * 0.48
    )
    let padPath = NSBezierPath(roundedRect: pad, xRadius: s * 0.055, yRadius: s * 0.055)
    padPath.lineWidth = max(1, s * 0.018)
    NSColor(white: 1, alpha: 0.22).setStroke()
    padPath.stroke()

    // Left (brightness) and right (volume) level bars.
    let barWidth = s * 0.055
    let barGap = s * 0.035
    let trackHeight = pad.height * 0.58
    let trackY = pad.midY - trackHeight / 2

    func bar(x: CGFloat, fraction: CGFloat, colour: NSColor) {
        let track = CGRect(x: x, y: trackY, width: barWidth, height: trackHeight)
        let trackPath = NSBezierPath(roundedRect: track, xRadius: barWidth / 2, yRadius: barWidth / 2)
        NSColor(white: 1, alpha: 0.14).setFill()
        trackPath.fill()

        let fillHeight = max(barWidth, trackHeight * fraction)
        let fill = CGRect(x: x, y: trackY, width: barWidth, height: fillHeight)
        let fillPath = NSBezierPath(roundedRect: fill, xRadius: barWidth / 2, yRadius: barWidth / 2)
        colour.setFill()
        fillPath.fill()
    }

    if let glow = NSGradient(colors: [
        NSColor(srgbRed: 1.0, green: 0.78, blue: 0.30, alpha: 1),
        NSColor(srgbRed: 1.0, green: 0.62, blue: 0.16, alpha: 1)
    ]) {
        glow.draw(in: NSBezierPath(roundedRect: CGRect(x: pad.minX + barGap, y: trackY, width: barWidth, height: trackHeight), xRadius: barWidth / 2, yRadius: barWidth / 2), angle: -90)
    }
    if let glow = NSGradient(colors: [
        NSColor(srgbRed: 0.42, green: 0.76, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.55, blue: 0.98, alpha: 1)
    ]) {
        glow.draw(in: NSBezierPath(roundedRect: CGRect(x: pad.maxX - barGap - barWidth, y: trackY, width: barWidth, height: trackHeight), xRadius: barWidth / 2, yRadius: barWidth / 2), angle: -90)
    }

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for variant in variants {
    let image = drawIcon(size: CGFloat(variant.pixels))
    guard let data = png(image, pixels: variant.pixels) else {
        FileHandle.standardError.write(Data("failed to render \(variant.name)\n".utf8))
        exit(1)
    }
    try data.write(to: iconset.appendingPathComponent("\(variant.name).png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    try? FileManager.default.removeItem(at: iconset)
    print("wrote \(icns.path)")
} else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}

import AppKit
import SlideSenseCore

// Diagnostic mode: stream raw trackpad contacts to stdout.
if CommandLine.arguments.contains("--dump-touches") {
    TrackpadDiagnostics.dump()
    exit(0)
}

if CommandLine.arguments.contains("--diagnose") {
    Diagnostics.printReport()
    exit(0)
}

// Development aid: cycle the HUD on screen (`--demo-hud`).
if CommandLine.arguments.contains("--demo-hud") {
    let demoApp = NSApplication.shared
    demoApp.setActivationPolicy(.accessory)
    let defaults = UserDefaults(suiteName: "io.github.slidesense.demo") ?? .standard
    let store = SettingsStore(defaults: defaults)
    let hud = HUDController(store: store)
    hud.show(edge: .volume, level: 0.64, muted: false)
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        hud.show(edge: .brightness, level: 0.86, muted: false)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
        hud.dismiss()
        exit(0)
    }
    demoApp.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

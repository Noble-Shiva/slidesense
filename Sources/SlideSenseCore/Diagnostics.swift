import CoreGraphics
import Foundation

/// `SlideSense --diagnose` prints everything needed to triage a bug report.
public enum Diagnostics {
    public static func printReport() {
        let audio = AudioController.shared
        let brightness = BrightnessController.shared

        print("SlideSense \(SlideSenseVersion.marketing) (\(SlideSenseVersion.build))")
        print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("")
        print("MultitouchSupport framework : \(TrackpadMonitor.isAvailable ? "available" : "MISSING")")
        print("Precise brightness control  : \(brightness.supportsPreciseControl ? "available" : "fallback to key events")")
        print("Accessibility permission    : \(AccessibilityPermission.isTrusted ? "granted" : "NOT granted")")
        print("Open at login supported     : \(LoginItem.isSupported ? "yes" : "no (running outside an .app bundle)")")
        print("")
        print(String(format: "Volume    : %.0f%%%@", audio.level * 100, audio.isMuted ? " (muted)" : ""))
        print(String(format: "Brightness: %.0f%%", brightness.level * 100))
        print("")
        print("Built-in displays: \(builtInDisplays().map(String.init).joined(separator: ", "))")
    }

    private static func builtInDisplays() -> [UInt32] {
        var count = UInt32(0)
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return displays.filter { CGDisplayIsBuiltin($0) != 0 }
    }
}

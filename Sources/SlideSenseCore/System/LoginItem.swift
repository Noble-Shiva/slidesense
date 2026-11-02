import Foundation
import ServiceManagement

/// "Open at login" via the modern `SMAppService` API (macOS 13+).
public enum LoginItem {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Only meaningful when running from a real `.app` bundle.
    public static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    @discardableResult
    public static func set(_ enabled: Bool) -> Bool {
        guard isSupported else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("SlideSense: could not update login item: \(error.localizedDescription)")
            return false
        }
    }

    /// Reconciles the stored preference with the real system state.
    public static func sync(_ wanted: Bool) {
        guard isSupported else { return }
        if wanted != isEnabled {
            _ = set(wanted)
        }
    }
}

import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let coordinator = AppCoordinator(store: .shared)
        self.coordinator = coordinator
        coordinator.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

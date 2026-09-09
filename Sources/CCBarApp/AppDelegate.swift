import AppKit
import CCBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var statusItemController: StatusItemController?
    private var refreshTimer: Timer?

    private static let refreshInterval: TimeInterval = 5 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(store: store)

        Task { await store.refresh() }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [store] _ in
            Task { @MainActor in await store.refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

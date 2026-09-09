import AppKit
import SwiftUI
import CCBarCore

/// NSPopover subclass that silently ignores an unrecognized key from the
/// `setValue(_:forKey:)` call below, instead of the Objective-C runtime's
/// default behavior of throwing an uncatchable exception. That call sets
/// a private, undocumented property (there's no public API to hide a
/// popover's arrow) — safe today, but this guards against a future macOS
/// version renaming or removing it and crashing the app outright.
private final class ArrowlessPopover: NSPopover {
    override func setValue(_ value: Any?, forUndefinedKey key: String) {}
}

/// Owns the menu bar status item and the popover it shows on click.
/// Left-click toggles the usage panel; right-click shows a small Quit
/// menu, using the standard "assign a menu just long enough to show it"
/// trick so left-click keeps using our own action the rest of the time.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let hostingView: NSHostingView<StatusItemContentView>
    private let store: UsageStore
    private var popover: NSPopover?
    private var outsideClickMonitor: Any?

    init(store: UsageStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hostingView = NSHostingView(rootView: StatusItemContentView(store: store))
        super.init()

        guard let button = statusItem.button else { return }
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)
        let fittingSize = hostingView.fittingSize
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            hostingView.heightAnchor.constraint(equalToConstant: fittingSize.height)
        ])
        statusItem.length = fittingSize.width

        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    deinit {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp {
            showQuitMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }

        let hostingController = NSHostingController(rootView: ExpandedPanelView(store: store))
        hostingController.sizingOptions = [.preferredContentSize]

        let newPopover = ArrowlessPopover()
        newPopover.behavior = .transient
        newPopover.delegate = self
        newPopover.contentViewController = hostingController
        // Hides the arrow/anchor that normally points back at the status
        // item — there's no public API for this, but this KVC key has
        // been the standard way to do it for years and is safe here since
        // ExpandedPanelView already provides its own visually-effect
        // background that reaches the popover's edges.
        newPopover.setValue(true, forKey: "shouldHideAnchor")

        // .transient's built-in outside-click dismissal can be unreliable
        // for an accessory-policy app (no Dock icon/regular activation),
        // since it partly depends on the app's own key/active-window
        // state. Activating explicitly, plus our own global click monitor
        // below, makes the close-on-outside-click behavior reliable
        // regardless of that.
        NSApp.activate(ignoringOtherApps: true)
        newPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        popover = newPopover
        installOutsideClickMonitor()
    }

    private func installOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let popover = self.popover, popover.isShown else { return }
            // Ignore clicks on the status item button itself — its own
            // action already handles toggling the popover closed.
            if let button = self.statusItem.button, let buttonWindow = button.window {
                let clickInButtonWindow = NSEvent.mouseLocation
                let buttonFrameOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
                if buttonFrameOnScreen.contains(clickInButtonWindow) {
                    return
                }
            }
            Task { @MainActor in
                popover.performClose(nil)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        popover = nil
    }

    private func showQuitMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit CCBar", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

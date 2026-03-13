import SwiftUI
import AppKit
import ServiceManagement
import Combine

// MARK: - App Entry Point

@main
struct ClawViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — this is a menu bar app
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var eventMonitor: Any?

    /// Floating panel for the detached/pinned mode (#63).
    var floatingPanel: NSPanel?
    /// Tracks whether the popover is currently detached as a floating panel (#63).
    var isPinned: Bool = false

    let gateway = GatewayService.shared
    let connectionManager = ConnectionManager()
    let iconController = MenuBarIconController()

    // Reactive icon updates via Combine — replaces 2s polling timer (#16)
    private var iconCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock (menu bar only app)
        NSApp.setActivationPolicy(.accessory)

        setupMenuBar()
        setupPopover()
        startServices()
        setupIconObserver()
    }

    // MARK: - Menu Bar Setup

    func setupMenuBar() {
        iconController.setup()

        guard let statusItem = iconController.statusItem else { return }
        self.statusItem = statusItem

        guard let button = statusItem.button else { return }
        button.action = #selector(handleStatusItemClick)
        button.target = self
        // Left click opens popover; right click shows context menu (#20)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Enable layer for Core Animation
        button.wantsLayer = true
    }

    // MARK: - Popover Setup

    func setupPopover() {
        let popover = NSPopover()
        // Fixed height: ScrollView with maxHeight:540 handles variable content (#38).
        // Dynamic sizing via updatePopoverSize() was using a wrong 80pt-per-card
        // constant, causing clips and blank space. Let SwiftUI layout win.
        popover.contentSize = NSSize(width: 320, height: 540)
        popover.behavior = .transient
        popover.animates = true

        let popoverView = PopoverView(
            gateway: gateway,
            connectionManager: connectionManager,
            isPinned: false,
            onPinToggled: { [weak self] in
                Task { @MainActor [weak self] in self?.togglePin() }
            }
        )
        popover.contentViewController = NSHostingController(rootView: popoverView)
        self.popover = popover

        // Close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover()
            }
        }
    }

    // MARK: - Click Handler

    @objc func handleStatusItemClick() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            // Right click → context menu (#20)
            showContextMenu()
        } else {
            // Left click → toggle popover
            togglePopover()
        }
    }

    // MARK: - Context Menu (#20, #6, #19)

    private func showContextMenu() {
        let menu = NSMenu()

        // Version info (#19) — immediately visible without digging into settings
        let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let buildString = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let versionLabel = buildString.isEmpty ? "ClawView v\(versionString)" : "ClawView v\(versionString) (\(buildString))"
        let versionItem = NSMenuItem(title: versionLabel, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(NSMenuItem.separator())

        // Open ClawView popover
        menu.addItem(withTitle: "Open ClawView", action: #selector(togglePopover), keyEquivalent: "")

        // Open Clawdia's Discord channel directly (#17 — useful deep link)
        let discordItem = NSMenuItem(title: "Open Clawdia in Discord", action: #selector(openClawdiaChannel), keyEquivalent: "")
        menu.addItem(discordItem)

        menu.addItem(NSMenuItem.separator())

        // Quit (#20 — no dock icon means no other way to quit)
        menu.addItem(withTitle: "Quit ClawView", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Show menu at status item
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        // Remove menu after showing so left-click still opens popover
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    // MARK: - Actions

    @objc func togglePopover() {
        if let popover = popover, popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    /// Open Clawdia's Discord channel directly (#17)
    @objc func openClawdiaChannel() {
        // Deep link to Clawdia's Discord channel
        // Format: discord://discord.com/channels/{guild_id}/{channel_id}
        let clawdiaChannelId = "1480700058067533886"
        let guildId = "1480268359474126998"
        if let url = URL(string: "discord://discord.com/channels/\(guildId)/\(clawdiaChannelId)") {
            NSWorkspace.shared.open(url)
        }
    }

    func openPopover() {
        guard let button = statusItem?.button,
              let popover = popover else { return }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    // MARK: - Floating Panel (Pin/Unpin) (#63)

    /// Toggles between popover mode and detached floating panel mode.
    /// Pin:   closes the popover → opens a persistent NSPanel at .floating window level
    /// Unpin: closes the floating panel → restores normal popover/click behaviour
    func togglePin() {
        if isPinned {
            unpin()
        } else {
            pin()
        }
    }

    private func pin() {
        isPinned = true

        // Close the popover — we're taking over with a panel
        popover?.performClose(nil)

        // Build the panel content with isPinned=true so the pin button shows as lit
        let pinnedView = PopoverView(
            gateway: gateway,
            connectionManager: connectionManager,
            isPinned: true,
            onPinToggled: { [weak self] in
                Task { @MainActor [weak self] in self?.togglePin() }
            }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 540),
            styleMask: [
                .titled,
                .closable,
                .fullSizeContentView,
                .nonactivatingPanel,   // doesn't steal focus from other apps
                .utilityWindow,        // smaller title bar, stays above most windows
            ],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating             // above normal windows
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.isReleasedWhenClosed = false

        // Position: near the status item, below the menu bar
        if let button = statusItem?.button, let screen = button.window?.screen ?? NSScreen.main {
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = button.window?.convertToScreen(buttonRect) ?? buttonRect
            let panelX = min(screenRect.minX, screen.frame.maxX - 330)
            let panelY = screen.frame.maxY - screen.visibleFrame.maxY + screen.visibleFrame.height - 550
            panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
        } else {
            panel.center()
        }

        let hostingController = NSHostingController(rootView: pinnedView)
        panel.contentViewController = hostingController

        // When the panel is closed via the close button, unpin cleanly
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isPinned else { return }
                self.isPinned = false
                self.floatingPanel = nil
                // Restore popover pin button to unlit state
                self.refreshPopoverContent()
            }
        }

        panel.orderFront(nil)
        self.floatingPanel = panel
    }

    private func unpin() {
        isPinned = false
        floatingPanel?.close()
        floatingPanel = nil
        // Refresh popover so it reopens with isPinned=false
        refreshPopoverContent()
    }

    /// Rebuilds the popover content view with the current isPinned state.
    /// Called after pin state changes so the pin button reflects reality.
    private func refreshPopoverContent() {
        let updatedView = PopoverView(
            gateway: gateway,
            connectionManager: connectionManager,
            isPinned: isPinned,
            onPinToggled: { [weak self] in
                Task { @MainActor [weak self] in self?.togglePin() }
            }
        )
        if let vc = popover?.contentViewController as? NSHostingController<PopoverView> {
            vc.rootView = updatedView
        }
    }

    // MARK: - Reactive Icon Updates (#16)
    // Replace 2-second polling timer with Combine subscription.
    // Icon updates when gateway publishes new data — not on an arbitrary clock.

    func setupIconObserver() {
        iconCancellable = gateway.$systemStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.iconController.updateFromGateway(self.gateway)
            }
    }

    // MARK: - Services

    func startServices() {
        if connectionManager.isFirstRun {
            // First run — show popover with setup screen
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                self.openPopover()
            }
        } else {
            connectionManager.reconnect()
        }
    }

    // Launch at Login is now controlled by SettingsView directly via
    // SMAppService.mainApp.register/unregister (#33). AppDelegate helpers removed.

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        iconCancellable?.cancel()
        gateway.disconnect()
    }
}

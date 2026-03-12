/**
 * ClawViewApp.swift
 * -----------------
 * Application entry point and NSApplicationDelegate for ClawView.
 *
 * ClawView is a macOS menu bar app (LSUIElement = true), so there is no Dock
 * icon and no main window. Everything lives in the NSStatusItem popover.
 *
 * This file owns:
 *   - The @main App struct (required by SwiftUI lifecycle)
 *   - AppDelegate, which sets up the menu bar item, popover, and coordinates
 *     the core services (GatewayService, ConnectionManager, MenuBarIconController)
 *   - Icon update timer (polls GatewayService every 2s to update icon state)
 *   - Launch-at-login registration via SMAppService (macOS 13+)
 */

import SwiftUI
import AppKit
import ServiceManagement

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

    let gateway = GatewayService.shared
    let connectionManager = ConnectionManager()
    let iconController = MenuBarIconController()

    // Timer to update icon state
    private var iconUpdateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock (menu bar only app)
        NSApp.setActivationPolicy(.accessory)

        setupMenuBar()
        setupPopover()
        startServices()
        setupIconUpdateTimer()
    }

    // MARK: - Menu Bar Setup

    func setupMenuBar() {
        iconController.setup()

        guard let statusItem = iconController.statusItem else { return }
        self.statusItem = statusItem

        guard let button = statusItem.button else { return }
        button.action = #selector(togglePopover)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Enable layer for Core Animation
        button.wantsLayer = true
    }

    // MARK: - Popover Setup

    func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.animates = true

        let popoverView = PopoverView(
            gateway: gateway,
            connectionManager: connectionManager
        )
        popover.contentViewController = NSHostingController(rootView: popoverView)
        self.popover = popover

        // Close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
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

    func openPopover() {
        guard let button = statusItem?.button,
              let popover = popover else { return }

        // Recalculate content height based on agent count
        updatePopoverSize()

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    private func updatePopoverSize() {
        let agentCount = gateway.allAgents.count
        let cardHeight = 80 // approx per card
        let headerHeight = 56
        let footerHeight = 44
        let bodyHeight = max(100, min(agentCount * cardHeight + 16, 392))
        let totalHeight = headerHeight + bodyHeight + footerHeight
        popover?.contentSize = NSSize(width: 320, height: totalHeight)
    }

    // MARK: - Services

    func startServices() {
        if connectionManager.isFirstRun {
            // First run — no saved connection settings yet.
            // Show the setup popover after a short delay so the menu bar item
            // has time to finish rendering before we call show(relativeTo:).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.openPopover()
            }
        } else {
            // Saved settings exist — reconnect immediately.
            connectionManager.reconnect()
        }
    }

    func setupIconUpdateTimer() {
        // Poll GatewayService every 2 seconds to drive icon state changes.
        // This is separate from the HTTP poll in GatewayService (every 5s) —
        // it just reads already-fetched data to keep the icon in sync.
        iconUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.iconController.updateFromGateway(self.gateway)
            }
        }
    }

    // MARK: - Launch at Login

    func enableLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }
    }

    func disableLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.unregister()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        iconUpdateTimer?.invalidate()
        gateway.disconnect()
    }
}

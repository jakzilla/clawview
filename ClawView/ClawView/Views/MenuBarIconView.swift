import Cocoa

// MARK: - Menu Bar Icon Manager
// Handles the NSStatusItem and icon state in AppKit.
// Exactly two states (#67):
//   .connected    — gateway reachable → solid white (template, macOS handles dark/light)
//   .disconnected — gateway unreachable → solid red

class MenuBarIconController: NSObject {
    var statusItem: NSStatusItem?

    /// Exactly two visible states (#67). All other conditions (active agents,
    /// stuck agents, warnings) are reflected in the popover — not the icon.
    enum IconState {
        case connected      // Gateway reachable — solid white template icon
        case disconnected   // Gateway unreachable — solid red icon
    }

    private var currentState: IconState = .disconnected

    // MARK: - Setup

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }
        button.image = menuBarImage(for: .disconnected)
        button.imageScaling = .scaleProportionallyUpOrDown
    }

    // MARK: - State Updates

    func setState(_ state: IconState) {
        guard state != currentState else { return }
        currentState = state

        DispatchQueue.main.async { [weak self] in
            self?.applyState(state)
        }
    }

    private func applyState(_ state: IconState) {
        guard let button = statusItem?.button else { return }

        let img = menuBarImage(for: state)
        button.image = img
        button.alphaValue = 1.0

        switch state {
        case .connected:
            // Template image — macOS renders as white in dark menu bar, black in light (#67)
            button.image?.isTemplate = true

        case .disconnected:
            // Non-template red image (#67) — gateway is gone, user needs to notice
            button.image?.isTemplate = false
        }
    }

    // MARK: - Image Generation

    /// Returns the menu bar image for the given state.
    /// Connected → template image (white/black per OS)
    /// Disconnected → red-tinted image
    private func menuBarImage(for state: IconState) -> NSImage {
        // Load the claw asset directly (#143 — PNG already regenerated without the side bar,
        // so trimmedToContent() workaround is no longer needed. Natural 18×18pt size restored.)
        let baseImage: NSImage
        if let asset = NSImage(named: "MenuBarIcon") {
            asset.size = NSSize(width: 18, height: 18)
            baseImage = asset
        } else {
            baseImage = drawFallbackIcon()
        }

        switch state {
        case .connected:
            baseImage.isTemplate = true
            return baseImage

        case .disconnected:
            // Tint the claw solid red — draw it with systemRed fill (#67)
            return tintedImage(baseImage, color: NSColor.systemRed)
        }
    }

    /// Returns a copy of `image` with all opaque pixels replaced by `color`.
    /// Used to produce the solid red disconnected icon (#67).
    private func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()

        // Draw the image as a mask, then apply the tint colour
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1.0)

        color.setFill()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)

        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    private func drawFallbackIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.labelColor.withAlphaComponent(0.85).setFill()

        // Simple claw shape
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 9, y: 14))
        path.curve(to: NSPoint(x: 4, y: 9),
                   controlPoint1: NSPoint(x: 6, y: 14),
                   controlPoint2: NSPoint(x: 4, y: 12))
        path.curve(to: NSPoint(x: 9, y: 4),
                   controlPoint1: NSPoint(x: 4, y: 6),
                   controlPoint2: NSPoint(x: 6, y: 4))
        path.curve(to: NSPoint(x: 14, y: 9),
                   controlPoint1: NSPoint(x: 12, y: 4),
                   controlPoint2: NSPoint(x: 14, y: 6))
        path.curve(to: NSPoint(x: 9, y: 14),
                   controlPoint1: NSPoint(x: 14, y: 12),
                   controlPoint2: NSPoint(x: 12, y: 14))
        path.fill()

        image.unlockFocus()
        return image
    }

    // MARK: - Derived State from GatewayService

    /// Maps gateway connection state to the two-state icon model (#67).
    /// Connected = any reachable state (local network or tunnel).
    /// Disconnected = gateway unreachable or error.
    /// All intermediate states (working, stuck, warning) are displayed
    /// in the popover only — not reflected in the icon.
    @MainActor func updateFromGateway(_ gateway: GatewayService) {
        let newState: IconState
        switch gateway.connectionState {
        case .disconnected, .error:
            newState = .disconnected
        case .localNetwork, .sshTunnel:
            newState = .connected
        }
        setState(newState)
    }
}

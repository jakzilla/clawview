import Cocoa

// MARK: - Menu Bar Icon Manager
// Handles the NSStatusItem and icon state/animation in AppKit.

class MenuBarIconController: NSObject {
    var statusItem: NSStatusItem?
    private var badgeLayer: CALayer?

    enum IconState {
        case idle           // Connected, nothing running
        case working        // Active agents
        case attention      // Warning — taking too long
        case error          // Error or stuck agent
        case disconnected   // Can't reach gateway
    }

    private var currentState: IconState = .disconnected

    // MARK: - Setup

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }
        button.image = menuBarImage(for: .disconnected)
        button.image?.isTemplate = true
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

        removeBadge()

        switch state {
        case .idle:
            button.image = menuBarImage(for: .idle)
            button.image?.isTemplate = true
            button.alphaValue = 1.0

        case .working:
            // Static icon — no pulse/animation (#65)
            button.image = menuBarImage(for: .working)
            button.image?.isTemplate = true
            button.alphaValue = 1.0

        case .attention:
            button.image = menuBarImage(for: .attention)
            button.image?.isTemplate = true
            button.alphaValue = 1.0
            addBadge(color: NSColor.systemYellow, to: button)

        case .error:
            button.image = menuBarImage(for: .error)
            button.image?.isTemplate = true
            button.alphaValue = 1.0
            addBadge(color: NSColor.systemRed, to: button)

        case .disconnected:
            button.image = menuBarImage(for: .disconnected)
            button.image?.isTemplate = false
            // Template false so we can control alpha manually
            button.image = dimmedImage(menuBarImage(for: .disconnected))
            button.alphaValue = 0.4
        }
    }

    // MARK: - Badge Layer

    private func addBadge(color: NSColor, to button: NSStatusBarButton) {
        guard let layer = button.layer else { return }

        removeBadge()

        let badge = CALayer()
        let badgeDiameter: CGFloat = 6
        let inset: CGFloat = 1

        // Position: top-right of button
        let buttonBounds = button.bounds
        badge.frame = CGRect(
            x: buttonBounds.width - badgeDiameter - inset,
            y: buttonBounds.height - badgeDiameter - inset,
            width: badgeDiameter,
            height: badgeDiameter
        )
        badge.cornerRadius = badgeDiameter / 2
        badge.backgroundColor = color.cgColor

        // White ring (punches out from menu bar)
        badge.borderColor = NSColor.windowBackgroundColor.cgColor
        badge.borderWidth = 1.0

        layer.addSublayer(badge)
        badgeLayer = badge
    }

    private func removeBadge() {
        badgeLayer?.removeFromSuperlayer()
        badgeLayer = nil
    }

    // MARK: - Image Generation

    private func menuBarImage(for state: IconState) -> NSImage {
        // Use the custom claw asset from the asset catalogue.
        // Template rendering intent is set in Contents.json so macOS handles
        // light/dark mode automatically when isTemplate = true.
        if let image = NSImage(named: "MenuBarIcon") {
            return image
        }

        // Fallback: draw a simple claw icon programmatically
        return drawFallbackIcon()
    }

    private func dimmedImage(_ image: NSImage) -> NSImage {
        // Return the image as-is; we control alpha via button.alphaValue
        return image
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

    @MainActor func updateFromGateway(_ gateway: GatewayService) {
        let newState: IconState
        switch gateway.connectionState {
        case .disconnected, .error:
            newState = .disconnected
        case .localNetwork, .sshTunnel:
            if gateway.hasStuckAgents {
                newState = .error
            } else if gateway.hasWarningAgents {
                newState = .attention
            } else if !gateway.activeAgents.isEmpty {
                newState = .working
            } else {
                newState = .idle
            }
        }
        setState(newState)
    }
}

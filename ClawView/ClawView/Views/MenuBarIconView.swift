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
            // Trim horizontal whitespace so the claw fills the canvas cleanly (#66).
            // The source asset has excess horizontal padding; trimmedToContent()
            // finds the tightest bounding box of non-transparent pixels and
            // re-renders the claw centred in an 18×18pt square.
            return trimmedToContent(image, targetSize: NSSize(width: 18, height: 18))
        }

        // Fallback: draw a simple claw icon programmatically
        return drawFallbackIcon()
    }

    /// Crops `source` to the tightest bounding box of opaque pixels,
    /// then scales the result to fit within `targetSize` with equal margins
    /// on all sides (at most 1pt padding). This removes horizontal whitespace
    /// baked into the source asset (#66).
    private func trimmedToContent(_ source: NSImage, targetSize: NSSize) -> NSImage {
        // Work at 2x for precision
        let scale: CGFloat = 2.0
        let srcW = Int(source.size.width * scale)
        let srcH = Int(source.size.height * scale)

        guard srcW > 0 && srcH > 0 else { return source }

        // Rasterise the source image into a bitmap
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: srcW,
            pixelsHigh: srcH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: srcW * 4,
            bitsPerPixel: 32
        ) else { return source }

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = ctx
        source.draw(in: CGRect(x: 0, y: 0, width: srcW, height: srcH))
        NSGraphicsContext.restoreGraphicsState()

        // Find bounding box of non-transparent pixels
        guard let data = rep.bitmapData else { return source }

        var minX = srcW, maxX = 0, minY = srcH, maxY = 0
        for y in 0..<srcH {
            for x in 0..<srcW {
                let offset = (y * srcW + x) * 4
                let alpha = data[offset + 3]
                if alpha > 10 {  // ignore near-transparent fringe
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        // If no opaque pixels found, return original
        guard minX <= maxX && minY <= maxY else { return source }

        let contentW = CGFloat(maxX - minX + 1)
        let contentH = CGFloat(maxY - minY + 1)

        // Scale content to fill targetSize with 1pt inset on each side (2px at 2x)
        let inset: CGFloat = 2.0  // 1pt at 2x
        let availW = targetSize.width * scale - inset * 2
        let availH = targetSize.height * scale - inset * 2
        let scaleRatio = min(availW / contentW, availH / contentH)

        let drawW = contentW * scaleRatio
        let drawH = contentH * scaleRatio
        let drawX = (targetSize.width * scale - drawW) / 2
        let drawY = (targetSize.height * scale - drawH) / 2

        // Create cropped source image (the tight bounding box)
        let cropRect = NSRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(srcH - maxY - 1) / scale,   // flip Y (AppKit coords)
            width: contentW / scale,
            height: contentH / scale
        )

        // Render final image at targetSize
        let result = NSImage(size: targetSize)
        result.lockFocus()
        source.draw(
            in: NSRect(x: drawX / scale, y: drawY / scale, width: drawW / scale, height: drawH / scale),
            from: cropRect,
            operation: .sourceOver,
            fraction: 1.0
        )
        result.unlockFocus()
        result.isTemplate = source.isTemplate
        return result
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

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
    /// Connected → trimmed template image (white/black per OS)
    /// Disconnected → trimmed red-tinted image
    private func menuBarImage(for state: IconState) -> NSImage {
        // Load and trim the source claw asset (#66)
        let baseImage: NSImage
        if let asset = NSImage(named: "MenuBarIcon") {
            baseImage = trimmedToContent(asset, targetSize: NSSize(width: 14, height: 18))
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

    /// Crops `source` to the tightest bounding box of opaque pixels,
    /// then scales the result to fit within `targetSize` with equal margins
    /// on all sides (at most 1pt padding). Removes horizontal whitespace
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

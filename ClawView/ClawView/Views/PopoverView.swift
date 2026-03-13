import SwiftUI

// MARK: - Main Popover View

struct PopoverView: View {
    @ObservedObject var gateway: GatewayService
    @ObservedObject var connectionManager: ConnectionManager
    @State private var showSettings = false

    /// Whether the view is currently displayed in a floating panel (#63).
    /// When true, the header shows a lit pin icon.
    var isPinned: Bool = false

    /// Callback invoked when the user taps the pin button (#63).
    /// The caller (AppDelegate) handles the actual panel/popover transition.
    var onPinToggled: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsView(
                    connectionManager: connectionManager,
                    onDismiss: { showSettings = false }
                )
            } else if connectionManager.isFirstRun {
                FirstRunView(connectionManager: connectionManager)
            } else {
                mainContent
            }
        }
        .frame(width: 320)
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Header — pass connectionManager so header can read display name (#28)
            PopoverHeaderView(
                gateway: gateway,
                connectionManager: connectionManager,
                isPinned: isPinned,
                onPinToggled: onPinToggled
            )

            // Body
            if gateway.connectionState == .disconnected {
                DisconnectedView(gateway: gateway)
            } else {
                AgentListView(gateway: gateway)
            }

            // Footer
            PopoverFooterView(
                gateway: gateway,
                onSettingsTapped: { showSettings = true }
            )
        }
    }
}

// MARK: - Header View

struct PopoverHeaderView: View {
    @ObservedObject var gateway: GatewayService
    /// Connection settings, used to read the user-configured display name (#28).
    var connectionManager: ConnectionManager? = nil
    /// Whether the view is currently in floating panel mode (#63).
    var isPinned: Bool = false
    /// Called when the user taps the pin button (#63).
    var onPinToggled: (() -> Void)? = nil
    @State private var heartbeatAge: String = "–"
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                // Status dot (#39)
                Circle()
                    .fill(connectionDotColor)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(connectionStateDescription)
                    .accessibilityAddTraits(.isStaticText)

                // System name — uses user display name if set, otherwise cleaned hostname (#28)
                Text(resolvedDisplayName)
                    .font(.system(.title3, design: .default, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                // Pin button — detach popover into floating panel (#63)
                Button(action: { onPinToggled?() }) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isPinned ? Color(NSColor.controlAccentColor) : Color(NSColor.tertiaryLabelColor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPinned ? "Unpin — return to popover" : "Pin — keep window open")
                .help(isPinned ? "Unpin (return to popover)" : "Pin (keep window open)")

                // "Updated X ago" — plain language, not "Last beat" jargon (#12)
                HStack(spacing: 2) {
                    Text("Updated")
                        .font(.caption)
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))

                    Text(heartbeatAge == "–" ? "–" : "\(heartbeatAge) ago")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(heartbeatTextColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: 56)

            // Stale data warning banner (#43) — shown when no gateway response for > 5 minutes.
            // heartbeatIsStale is a computed var on GatewayService (> 90s, #88).
            // Reduced from 300s: 90s = ~3 missed poll cycles — fast enough to warn
            // without false-alarming on transient connectivity blips.
            if gateway.heartbeatIsStale {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)  // text label conveys the meaning (#39)
                    Text("Gateway unreachable — data is \(heartbeatAge) old")
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundColor(Color(NSColor.systemYellow))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .background(Color(NSColor.systemYellow).opacity(0.12))
            }

            Divider()
        }
        .onReceive(timer) { _ in
            heartbeatAge = gateway.heartbeatAge
        }
        .onAppear {
            heartbeatAge = gateway.heartbeatAge
        }
    }

    /// Resolves the best available display name for the connected host (#28).
    /// Priority: user display name > cleaned hostname > raw hostname > "OpenClaw"
    ///
    /// connectionManager is optional to allow SwiftUI previews to construct
    /// PopoverHeaderView without a full ConnectionManager instance.
    private var resolvedDisplayName: String {
        // 1. User-configured display name takes priority
        if let userDisplay = connectionManager?.settings.displayName {
            let trimmed = userDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        // 2. Clean the raw hostname from the API
        if let raw = gateway.systemStatus?.hostname {
            return GatewayService.cleanHostname(raw)
        }
        // 3. Fall back to a safe default
        return "OpenClaw"
    }

    /// Human-readable connection state for VoiceOver (#39)
    private var connectionStateDescription: String {
        switch gateway.connectionState {
        case .localNetwork: return "Connection: local network"
        case .sshTunnel: return "Connection: remote tunnel"
        case .disconnected: return "Connection: disconnected"
        case .error: return "Connection: error"
        }
    }

    private var connectionDotColor: Color {
        switch gateway.connectionState {
        case .localNetwork: return Color(NSColor.systemGreen)
        case .sshTunnel: return Color(NSColor.systemBlue)
        case .disconnected: return Color(NSColor.systemGray)
        case .error: return Color(NSColor.systemRed)
        }
    }

    private var heartbeatTextColor: Color {
        guard let lastHeartbeat = gateway.lastHeartbeat else {
            return Color(NSColor.systemRed)
        }
        let elapsed = Date().timeIntervalSince(lastHeartbeat)
        if elapsed < 300 { return Color(NSColor.secondaryLabelColor) }
        if elapsed < 600 { return Color(NSColor.systemYellow) }
        return Color(NSColor.systemRed)
    }
}

// MARK: - Agent List View

struct AgentListView: View {
    @ObservedObject var gateway: GatewayService

    /// Set to true after the first successful data fetch (#132).
    /// Prevents the "All quiet" moon from flashing during the ~5s initial load.
    @State private var hasLoadedOnce: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if gateway.allAgents.isEmpty && !hasLoadedOnce {
                    // Loading state — shown until first successful response (#132)
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading…")
                            .font(.subheadline)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else if gateway.allAgents.isEmpty {
                    IdleStateView()
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(gateway.allAgents.enumerated()), id: \.element.id) { index, agent in
                            AgentCardView(agent: agent, index: index)

                            if index < gateway.allAgents.count - 1 {
                                Divider()
                                    .padding(.leading, 56) // Align with text, not emoji
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(minHeight: 440, maxHeight: 540) // min forces panel to expand; max caps popover — fix #141
        .scrollIndicators(.hidden)
        // Mark first load complete as soon as gateway responds (#132)
        // Use lastHeartbeat as the signal — it's set on every successful fetch
        .onChange(of: gateway.lastHeartbeat) { _ in
            if !hasLoadedOnce { hasLoadedOnce = true }
        }
        .onAppear {
            // If already loaded before this view appeared (e.g. popover re-opened), don't re-show loader
            if gateway.lastHeartbeat != nil { hasLoadedOnce = true }
        }
    }
}

// MARK: - Idle State View

struct IdleStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("🌙")
                .font(.system(size: 24))

            Text("All quiet")
                .font(.headline)
                .foregroundColor(.primary)

            Text("No agents are running.\nThe system is idle.")
                .font(.subheadline)
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
    }
}

// MARK: - Disconnected View

struct DisconnectedView: View {
    @ObservedObject var gateway: GatewayService

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .accessibilityHidden(true)  // decorative; text below conveys the state (#39)

            VStack(spacing: 6) {
                // Use configured host rather than hardcoded "Mac mini" (#35)
                // gateway.host is the address the user configured; empty means not yet set.
                let hostLabel = gateway.host.isEmpty ? "OpenClaw" : gateway.host
                Text("Can't reach \(hostLabel)")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text("Check that OpenClaw is running\nand your network connection is active.")
                    .font(.subheadline)
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .multilineTextAlignment(.center)
            }

            Button("Try Again") {
                Task {
                    await gateway.fetchStatus()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(width: 120, height: 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
    }
}

// MARK: - Footer View

struct PopoverFooterView: View {
    @ObservedObject var gateway: GatewayService
    var onSettingsTapped: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                // Clawdia Discord button removed (#68) — was failing silently
                FooterButton(
                    label: "Settings",
                    icon: "gearshape",
                    enabled: true,
                    action: onSettingsTapped
                )
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
        }
    }
}

struct FooterButton: View {
    let label: String
    let icon: String
    let enabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .accessibilityHidden(true)  // label Text already conveys purpose (#39)
                Text(label)
                    .font(.system(.caption, weight: .medium))
            }
            .foregroundColor(enabled ? Color(NSColor.controlAccentColor) : Color(NSColor.tertiaryLabelColor))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered && enabled ? Color(NSColor.quaternaryLabelColor) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hover
            }
        }
        .onExitCommand {
            isHovered = false
        }
    }
}

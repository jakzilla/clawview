import SwiftUI

// MARK: - Main Popover View

struct PopoverView: View {
    @ObservedObject var gateway: GatewayService
    @ObservedObject var connectionManager: ConnectionManager
    @State private var showSettings = false

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
            PopoverHeaderView(gateway: gateway, connectionManager: connectionManager)

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
    @State private var heartbeatAge: String = "–"
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                // Status dot
                Circle()
                    .fill(connectionDotColor)
                    .frame(width: 8, height: 8)

                // System name — uses user display name if set, otherwise cleaned hostname (#28)
                Text(resolvedDisplayName)
                    .font(.system(.title3, design: .default, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

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
            // heartbeatIsStale is a computed var on GatewayService (> 300s).
            if gateway.heartbeatIsStale {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Data may be outdated — last updated \(heartbeatAge) ago")
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

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if gateway.allAgents.isEmpty {
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
        .frame(maxHeight: 540) // 640 - 56 (header) - 44 (footer) — v1.1 height fix
        .scrollIndicators(.hidden)
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
                // Discord button — deep links to Clawdia's channel, not just open Discord (#17)
                FooterButton(
                    label: "Clawdia",
                    icon: "arrow.up.forward.square",
                    enabled: gateway.connectionState != .disconnected
                ) {
                    openClawdiaChannel()
                }

                // "Processes" removed — permanently disabled button is a broken promise (#6)
                // Will return when process viewer is implemented in v1.1

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

    /// Deep link to Clawdia's Discord channel (#17)
    private func openClawdiaChannel() {
        let clawdiaChannelId = "1480700058067533886"
        let guildId = "1480268359474126998"
        if let url = URL(string: "discord://discord.com/channels/\(guildId)/\(clawdiaChannelId)") {
            NSWorkspace.shared.open(url)
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

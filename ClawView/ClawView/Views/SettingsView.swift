import SwiftUI
import ServiceManagement

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var connectionManager: ConnectionManager
    var onDismiss: () -> Void

    @State private var host: String = ""
    @State private var portString: String = ""
    @State private var useMock: Bool = false
    @State private var displayName: String = ""
    /// Launch at Login toggle state — read from SMAppService on appear (#33).
    @State private var launchAtLogin: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                    Text("Back")
                        .font(.system(.caption, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(NSColor.controlAccentColor))

                Spacer()

                Text("Settings")
                    .font(.system(.headline, weight: .semibold))

                Spacer()

                // Balance the back button
                Text("Back")
                    .font(.system(.caption, weight: .medium))
                    .opacity(0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: 56)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // General section (#33) — Launch at Login
                    // SMAppService is available on macOS 13+. Below 13 the toggle
                    // is hidden to avoid showing broken UI.
                    if #available(macOS 13.0, *) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("GENERAL")
                                .font(.system(.caption, weight: .semibold))
                                .foregroundColor(.secondary)
                                .tracking(0.5)

                            Toggle("Launch at Login", isOn: $launchAtLogin)
                                .font(.subheadline)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(NSColor.quaternarySystemFill))
                                )
                                .onChange(of: launchAtLogin) { enabled in
                                    // If SMAppService call fails, revert toggle
                                    // so UI doesn't show a false state (#33 Codex review)
                                    do {
                                        if enabled {
                                            try SMAppService.mainApp.register()
                                        } else {
                                            try SMAppService.mainApp.unregister()
                                        }
                                    } catch {
                                        launchAtLogin = !enabled
                                    }
                                }
                        }
                    }

                    // Connection section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CONNECTION")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundColor(.secondary)
                            .tracking(0.5)

                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Host")
                                    .font(.system(.caption, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("griffin.local or IP address", text: $host)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Port")
                                    .font(.system(.caption, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("7317", text: $portString)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body)
                            }

                            // Display name override (#28): friendly label shown in the
                            // popover header instead of the raw OS hostname.
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Display name (optional)")
                                    .font(.system(.caption, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("e.g. Mac mini, Home Server", text: $displayName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body)
                                Text("Overrides the hostname shown in the header.")
                                    .font(.caption2)
                                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.quaternarySystemFill))
                        )
                    }

                    // Developer section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DEVELOPER")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundColor(.secondary)
                            .tracking(0.5)

                        Toggle("Use mock data", isOn: $useMock)
                            .font(.subheadline)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.quaternarySystemFill))
                            )
                    }

                    // Save button
                    Button("Save & Connect") {
                        connectionManager.settings.host = host
                        connectionManager.settings.port = Int(portString) ?? 7317
                        connectionManager.settings.useMockData = useMock
                        connectionManager.settings.displayName = displayName
                        connectionManager.saveAndConnect()
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)

                    // Version — read from bundle, not hardcoded (#126)
                    // Same logic as ClawViewApp.showContextMenu() for consistency
                    let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                    let buildString = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
                    let versionLabel = buildString.isEmpty
                        ? "ClawView v\(versionString) · OpenClaw"
                        : "ClawView v\(versionString) (\(buildString)) · OpenClaw"
                    Text(versionLabel)
                        .font(.caption2)
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(16)
            }
        }
        .onAppear {
            host = connectionManager.settings.host
            portString = String(connectionManager.settings.port)
            useMock = connectionManager.settings.useMockData
            displayName = connectionManager.settings.displayName
            // Read current launch-at-login state from SMAppService (#33)
            if #available(macOS 13.0, *) {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

// MARK: - First Run View

struct FirstRunView: View {
    @ObservedObject var connectionManager: ConnectionManager

    @State private var host: String = "localhost"
    @State private var portString: String = "7317"
    @State private var isSearching: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0)

            VStack(spacing: 20) {
                // Icon — lobster emoji as interim branding (#34).
                // pawprint.fill was never appropriate (evokes pet app).
                // Replace with custom claw SVG asset when it ships (see icon issue #40).
                Text("🦞")
                    .font(.system(size: 48))
                    .padding(.top, 24)

                VStack(spacing: 6) {
                    Text("Welcome to ClawView")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("Connect to your OpenClaw system\nto see what your agents are up to.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Connection form
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Host")
                            .font(.system(.caption, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField("griffin.local", text: $host)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Port")
                            .font(.system(.caption, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField("7317", text: $portString)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.quaternarySystemFill))
                )

                // Bonjour hint
                if connectionManager.bonjourDiscovery.isSearching {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text("Searching for OpenClaw on your network…")
                            .font(.caption2)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    }
                } else if !connectionManager.bonjourDiscovery.discoveredHosts.isEmpty {
                    VStack(spacing: 4) {
                        Text("Found on your network:")
                            .font(.caption2)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))

                        ForEach(connectionManager.bonjourDiscovery.discoveredHosts) { discovered in
                            Button(discovered.name) {
                                connectionManager.connectToDiscovered(discovered)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                } else {
                    Text("ClawView will auto-detect local instances via Bonjour.")
                        .font(.caption2)
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        .multilineTextAlignment(.center)
                }

                // Connect button
                Button("Connect") {
                    connectionManager.settings.host = host
                    connectionManager.settings.port = Int(portString) ?? 7317
                    connectionManager.saveAndConnect()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .font(.system(.body, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 32)

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            connectionManager.bonjourDiscovery.startDiscovery()
        }
        // Pre-fill from bonjour
        .onChange(of: connectionManager.bonjourDiscovery.discoveredHosts) { hosts in
            if let first = hosts.first {
                host = first.hostname
                portString = String(first.port)
            }
        }
    }
}

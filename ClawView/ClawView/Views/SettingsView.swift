import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var connectionManager: ConnectionManager
    var onDismiss: () -> Void

    @State private var host: String = ""
    @State private var portString: String = ""
    @State private var useMock: Bool = false

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
                                TextField("3917", text: $portString)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body)
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
                        connectionManager.settings.port = Int(portString) ?? 3917
                        connectionManager.settings.useMockData = useMock
                        connectionManager.saveAndConnect()
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)

                    // Version
                    Text("ClawView v0.1 · OpenClaw")
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
        }
    }
}

// MARK: - First Run View

struct FirstRunView: View {
    @ObservedObject var connectionManager: ConnectionManager

    @State private var host: String = "localhost"
    @State private var portString: String = "3917"
    @State private var isSearching: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0)

            VStack(spacing: 20) {
                // Icon — pawprint.fill placeholder until custom claw asset is ready (#1)
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Color(NSColor.controlAccentColor))
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
                        TextField("3917", text: $portString)
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
                    connectionManager.settings.port = Int(portString) ?? 3917
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

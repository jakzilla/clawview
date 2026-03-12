/**
 * ConnectionManager.swift
 * -----------------------
 * Manages connection settings and the first-run experience.
 *
 * Settings (host, port, mock mode) are persisted to UserDefaults under the key
 * `clawview_connection`. On first launch (no saved settings), `isFirstRun` is
 * true and the popover shows the onboarding/setup screen instead of agent data.
 *
 * Key responsibilities:
 *   - Persist and restore ConnectionSettings via UserDefaults
 *   - Detect first-run state
 *   - Initiate or reconnect the GatewayService polling loop
 *   - Provide mock mode (injects SystemStatus.mock into GatewayService for
 *     UI development without a live OpenClaw system)
 *   - Accept a discovered Bonjour host and immediately connect to it
 */

import Foundation
import Combine

// MARK: - Connection Settings

struct ConnectionSettings: Codable {
    var host: String
    var port: Int
    var useMockData: Bool

    static let defaultSettings = ConnectionSettings(
        host: "localhost",
        port: 7317,
        useMockData: false
    )

    static let storageKey = "clawview_connection"
}

// MARK: - ConnectionManager

@MainActor
class ConnectionManager: ObservableObject {
    @Published var settings: ConnectionSettings
    @Published var isFirstRun: Bool
    @Published var gatewayService = GatewayService.shared
    @Published var bonjourDiscovery = BonjourDiscovery()

    init() {
        if let data = UserDefaults.standard.data(forKey: ConnectionSettings.storageKey),
           let saved = try? JSONDecoder().decode(ConnectionSettings.self, from: data) {
            self.settings = saved
            self.isFirstRun = false
        } else {
            self.settings = ConnectionSettings.defaultSettings
            self.isFirstRun = true
        }
    }

    func saveAndConnect() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: ConnectionSettings.storageKey)
        }
        isFirstRun = false

        if settings.useMockData {
            startMockMode()
        } else {
            gatewayService.connect(host: settings.host, port: settings.port)
        }
    }

    func startMockMode() {
        // Inject mock data for UI development
        gatewayService.systemStatus = SystemStatus.mock
        gatewayService.connectionState = .localNetwork
        gatewayService.lastHeartbeat = Date()
    }

    func reconnect() {
        if settings.useMockData {
            startMockMode()
        } else {
            gatewayService.connect(host: settings.host, port: settings.port)
        }
    }

    func connectToDiscovered(_ host: BonjourDiscovery.DiscoveredHost) {
        settings.host = host.hostname
        settings.port = host.port
        saveAndConnect()
    }
}

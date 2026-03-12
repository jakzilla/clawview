import Foundation
import Combine

// MARK: - Connection Settings

struct ConnectionSettings: Codable {
    var host: String
    var port: Int
    var useMockData: Bool
    /// Optional user-configured friendly name for the host (e.g. "Home Mac mini").
    /// When set, this overrides the cleaned hostname in the popover header (#28).
    var displayName: String

    static let defaultSettings = ConnectionSettings(
        host: "localhost",
        port: 7317,
        useMockData: false,
        displayName: ""
    )

    static let storageKey = "clawview_connection"

    // Backwards-compatible decode: `displayName` was added in #28,
    // existing persisted settings won't have the key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decode(Int.self, forKey: .port)
        useMockData = try c.decode(Bool.self, forKey: .useMockData)
        displayName = (try? c.decode(String.self, forKey: .displayName)) ?? ""
    }

    init(host: String, port: Int, useMockData: Bool, displayName: String = "") {
        self.host = host
        self.port = port
        self.useMockData = useMockData
        self.displayName = displayName
    }
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

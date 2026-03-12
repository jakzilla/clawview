import Foundation
import Combine
import Network

// MARK: - Gateway API Models

struct GatewaySession: Codable {
    let key: String
    let agentId: String?
    let channel: String?
    let lastActivity: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case key
        case agentId = "agent_id"
        case channel
        case lastActivity = "last_activity"
        case status
    }
}

struct GatewaySessionsResponse: Codable {
    let sessions: [GatewaySession]?
    // The API might return an array or object — handle both
}

// MARK: - GatewayService

@MainActor
class GatewayService: ObservableObject {
    @Published var systemStatus: SystemStatus?
    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastHeartbeat: Date?
    @Published var errorMessage: String?

    private var pollingTask: Task<Void, Never>?
    private var webSocketTask: URLSessionWebSocketTask?
    /// Custom URLSession with tight timeouts (#30).
    /// Default URLSession.shared allows 60s per request — far too long for a
    /// local/LAN gateway poll. 8s request timeout means a hung gateway surfaces
    /// as a disconnect within one poll cycle, not after a 60s freeze.
    private var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8   // per-request: gateway must start responding within 8s
        config.timeoutIntervalForResource = 10 // total resource load: 10s hard cap
        return URLSession(configuration: config)
    }()

    // Connection config
    private(set) var host: String = ""
    private(set) var port: Int = 7317

    static let shared = GatewayService()
    private init() {}

    // MARK: - Connection Management

    func connect(host: String, port: Int) {
        self.host = host
        self.port = port
        startPolling()
    }

    func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil
        webSocketTask?.cancel()
        webSocketTask = nil
        connectionState = .disconnected
    }

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            // Exponential backoff on consecutive failures (#29).
            // Base interval: 5s. Doubles per failure up to a 120s cap.
            // Resets to 5s immediately on success.
            var consecutiveFailures = 0
            while !Task.isCancelled {
                let success = await fetchStatus()
                if success {
                    consecutiveFailures = 0
                } else {
                    consecutiveFailures += 1
                }
                // delay = 5s * 2^(failures-1), capped at 120s, minimum 5s
                let delay = consecutiveFailures == 0
                    ? 5.0
                    : min(5.0 * pow(2.0, Double(consecutiveFailures - 1)), 120.0)
                let delayNs = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delayNs)
            }
        }
    }

    // MARK: - API Calls

    /// Fetches the current gateway status. Returns `true` on success, `false` on any failure.
    @discardableResult
    func fetchStatus() async -> Bool {
        guard !host.isEmpty else {
            connectionState = .disconnected
            return false
        }

        // Try the dedicated /api/clawview/status endpoint first
        // Fall back to /api/sessions if needed
        do {
            let status = try await fetchClawViewStatus()
            systemStatus = status
            lastHeartbeat = Date()
            connectionState = .localNetwork
            errorMessage = nil
            return true
        } catch {
            // Try fallback
            do {
                let status = try await buildStatusFromSessions()
                systemStatus = status
                lastHeartbeat = Date()
                connectionState = .localNetwork
                errorMessage = nil
                return true
            } catch {
                connectionState = .disconnected
                errorMessage = error.localizedDescription
                return false
            }
        }
    }

    private func fetchClawViewStatus() async throws -> SystemStatus {
        let url = URL(string: "http://\(host):\(port)/api/clawview/status")!
        let (data, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SystemStatus.self, from: data)
    }

    private func buildStatusFromSessions() async throws -> SystemStatus {
        // Fetch sessions list
        let sessionsURL = URL(string: "http://\(host):\(port)/api/sessions")!
        let (sessionsData, sessionsResponse) = try await urlSession.data(from: sessionsURL)

        guard let httpResponse = sessionsResponse as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // Parse raw sessions JSON
        guard let json = try JSONSerialization.jsonObject(with: sessionsData) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        // Build agent infos from sessions
        var agents: [AgentInfo] = []

        // Sessions is a dict keyed by session key
        if let sessions = json as? [String: [String: Any]] {
            for (key, session) in sessions {
                let agentId = (session["agent_id"] as? String) ?? key
                let agentName = resolveAgentName(from: agentId)
                let agentEmoji = resolveAgentEmoji(from: agentId)
                let agentRole = resolveAgentRole(from: agentId)
                let lastMsg = session["last_message"] as? String ?? ""
                let activity = extractActivity(from: lastMsg, agentName: agentName)

                let lastActivityStr = session["last_activity"] as? String
                let lastActivity = parseDate(lastActivityStr)
                let health = computeHealth(lastActivity: lastActivity)

                let agent = AgentInfo(
                    id: agentId,
                    name: agentName,
                    emoji: agentEmoji,
                    role: agentRole,
                    status: health == .idle ? "idle" : "active",
                    activity: activity,
                    durationSeconds: 0,
                    health: health,
                    lastActivity: lastActivity,
                    channel: session["channel"] as? String,
                    subAgents: [],
                    cost: nil
                )
                agents.append(agent)
            }
        }

        return SystemStatus(
            hostname: host,
            uptime: "–",
            connection: "local",
            agents: agents,
            timestamp: Date()
        )
    }

    // MARK: - Helpers

    private func resolveAgentName(from id: String) -> String {
        let map: [String: String] = [
            "main": "Clawdia",
            "dev": "Linus",
            "jony": "Steve",
            "marketing": "Richard",
            "research": "Demis",
            "pa": "Prawn",
            "intake": "Santa"
        ]
        return map[id] ?? id.capitalized
    }

    private func resolveAgentEmoji(from id: String) -> String {
        let map: [String: String] = [
            "main": "🦞",
            "dev": "⚙️",
            "jony": "🦞",
            "marketing": "📣",
            "research": "🔬",
            "pa": "🎩",
            "intake": "🎅"
        ]
        return map[id] ?? "🤖"
    }

    private func resolveAgentRole(from id: String) -> String {
        let map: [String: String] = [
            "main": "Chief of Staff",
            "dev": "Engineering",
            "jony": "Product",
            "marketing": "Marketing",
            "research": "Research",
            "pa": "Personal Assistant",
            "intake": "Intake"
        ]
        return map[id] ?? "Agent"
    }

    private func extractActivity(from message: String, agentName: String) -> String {
        if message.isEmpty { return "Idle" }
        // Take first ~80 chars of last message as activity
        let truncated = message.prefix(80)
        return String(truncated)
    }

    private func computeHealth(lastActivity: Date?) -> AgentHealth {
        guard let lastActivity = lastActivity else { return .idle }
        let elapsed = Date().timeIntervalSince(lastActivity)
        if elapsed < 120 { return .normal }
        if elapsed < 600 { return .takingAWhile }
        return .stuck
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }

    // MARK: - Computed Properties

    var activeAgents: [AgentInfo] {
        systemStatus?.agents.filter { $0.isActive } ?? []
    }

    var allAgents: [AgentInfo] {
        systemStatus?.agents ?? []
    }

    var hasStuckAgents: Bool {
        allAgents.contains { $0.health == .stuck }
    }

    var hasWarningAgents: Bool {
        allAgents.contains { $0.health == .takingAWhile || $0.health == .stuck }
    }

    var heartbeatAge: String {
        guard let lastHeartbeat = lastHeartbeat else { return "–" }
        let elapsed = Int(Date().timeIntervalSince(lastHeartbeat))
        if elapsed < 60 { return "\(elapsed)s" }
        return "\(elapsed / 60)m"
    }

    var heartbeatIsStale: Bool {
        guard let lastHeartbeat = lastHeartbeat else { return true }
        return Date().timeIntervalSince(lastHeartbeat) > 300
    }
}

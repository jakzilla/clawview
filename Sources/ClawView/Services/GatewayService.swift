/**
 * GatewayService.swift
 * --------------------
 * Responsible for all HTTP communication with the ClawView status server.
 *
 * The service polls `http://<host>:<port>/api/clawview/status` every 5 seconds.
 * If that endpoint fails (e.g. running an older status server version), it falls
 * back to `/api/sessions` and constructs a SystemStatus from raw session data.
 *
 * All @Published properties are observed by SwiftUI views and the
 * MenuBarIconController. The service is a singleton (@MainActor) to keep all
 * state mutations on the main thread without explicit dispatch calls.
 *
 * Polling is driven by a Swift structured-concurrency Task with a 5s sleep loop
 * rather than a Timer, so it's naturally cancellable and plays well with
 * async/await throughout.
 */

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
    private var urlSession = URLSession.shared

    // Connection config
    private(set) var host: String = ""
    private(set) var port: Int = 3917

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
            while !Task.isCancelled {
                await fetchStatus()
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s poll
            }
        }
    }

    // MARK: - API Calls

    func fetchStatus() async {
        guard !host.isEmpty else {
            connectionState = .disconnected
            return
        }

        // Try the dedicated /api/clawview/status endpoint first
        // Fall back to /api/sessions if needed
        do {
            let status = try await fetchClawViewStatus()
            systemStatus = status
            lastHeartbeat = Date()
            connectionState = .localNetwork
            errorMessage = nil
        } catch {
            // Try fallback
            do {
                let status = try await buildStatusFromSessions()
                systemStatus = status
                lastHeartbeat = Date()
                connectionState = .localNetwork
                errorMessage = nil
            } catch {
                connectionState = .disconnected
                errorMessage = error.localizedDescription
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
        // Fallback path: the dedicated /api/clawview/status endpoint isn't available,
        // so we build a SystemStatus manually from the raw /api/sessions response.
        // This gives a degraded but functional view — less activity detail, but
        // connection/agent presence info is still accurate.
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

import Foundation

// MARK: - Agent Status Models

enum AgentHealth: String, Codable {
    case normal = "normal"
    case takingAWhile = "taking_a_while"
    case stuck = "stuck"
    case idle = "idle"
}

enum ConnectionState: String {
    case localNetwork
    case sshTunnel
    case disconnected
    case error
}

struct SubAgentInfo: Identifiable, Codable {
    let id: String
    let label: String
    let status: String
    let durationSeconds: Int

    enum CodingKeys: String, CodingKey {
        case id, label, status
        case durationSeconds = "duration_seconds"
    }

    /// Custom decoder so that a missing `id` from the live API never causes a
    /// silent decode failure.  The Gateway currently omits `id` from sub-agent
    /// objects (see issue #25); we generate a stable-enough UUID fallback so
    /// the array decodes cleanly.  All other fields use defensive decoding for
    /// the same reason.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.label = (try? container.decode(String.self, forKey: .label)) ?? "sub-agent"
        self.status = (try? container.decode(String.self, forKey: .status)) ?? "idle"
        self.durationSeconds = (try? container.decode(Int.self, forKey: .durationSeconds)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(status, forKey: .status)
        try container.encode(durationSeconds, forKey: .durationSeconds)
    }
}

struct AgentCost: Codable {
    let sessionTotal: Double

    enum CodingKeys: String, CodingKey {
        case sessionTotal = "session_total"
    }
}

/// A single real activity entry from the Gateway API.
/// Decoded from the `_recentActivity` array in `/api/clawview/status`.
struct RecentActivityEntry: Identifiable, Codable {
    let id: UUID
    let time: Date
    let text: String

    enum CodingKeys: String, CodingKey {
        case time, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.text = try container.decode(String.self, forKey: .text)
        // time is an ISO8601 string
        let timeString = try container.decode(String.self, forKey: .time)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timeString) {
            self.time = date
        } else {
            // Fallback without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            self.time = formatter.date(from: timeString) ?? Date()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(formatter.string(from: time), forKey: .time)
        try container.encode(text, forKey: .text)
    }

    /// Human-readable "HH:mm" from the entry's timestamp
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: time)
    }
}

struct AgentInfo: Identifiable, Codable {
    let id: String
    let name: String
    let emoji: String
    let role: String
    let status: String          // "active" | "idle"
    let activity: String
    let durationSeconds: Int
    let health: AgentHealth
    let lastActivity: Date?
    let channel: String?
    let subAgents: [SubAgentInfo]
    let cost: AgentCost?
    /// Real activity feed from Gateway — replaces mockActivities in AgentCardView
    let recentActivity: [RecentActivityEntry]

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, role, status, activity, health, channel, cost
        case durationSeconds = "duration_seconds"
        case lastActivity = "last_activity"
        case subAgents = "sub_agents"
        case recentActivity = "_recentActivity"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        emoji = try container.decode(String.self, forKey: .emoji)
        role = try container.decode(String.self, forKey: .role)
        status = try container.decode(String.self, forKey: .status)
        activity = try container.decode(String.self, forKey: .activity)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
        health = try container.decodeIfPresent(AgentHealth.self, forKey: .health) ?? .idle
        channel = try container.decodeIfPresent(String.self, forKey: .channel)
        cost = try container.decodeIfPresent(AgentCost.self, forKey: .cost)
        subAgents = try container.decodeIfPresent([SubAgentInfo].self, forKey: .subAgents) ?? []
        recentActivity = try container.decodeIfPresent([RecentActivityEntry].self, forKey: .recentActivity) ?? []

        // lastActivity — ISO8601 date
        if let lastActivityStr = try container.decodeIfPresent(String.self, forKey: .lastActivity) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: lastActivityStr) {
                lastActivity = date
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                lastActivity = formatter.date(from: lastActivityStr)
            }
        } else {
            lastActivity = nil
        }
    }

    /// Direct memberwise init — used by fallback session builder in GatewayService.
    init(id: String, name: String, emoji: String, role: String, status: String,
         activity: String, durationSeconds: Int, health: AgentHealth,
         lastActivity: Date?, channel: String?, subAgents: [SubAgentInfo],
         cost: AgentCost?, recentActivity: [RecentActivityEntry] = []) {
        self.id = id; self.name = name; self.emoji = emoji; self.role = role
        self.status = status; self.activity = activity
        self.durationSeconds = durationSeconds; self.health = health
        self.lastActivity = lastActivity; self.channel = channel
        self.subAgents = subAgents; self.cost = cost
        self.recentActivity = recentActivity
    }

    // Computed helper
    var isActive: Bool { status == "active" }
}

struct SystemStatus: Codable {
    let hostname: String
    let uptime: String
    let connection: String
    let agents: [AgentInfo]
    let timestamp: Date?

    enum CodingKeys: String, CodingKey {
        case hostname, uptime, connection, agents, timestamp
    }
}

// MARK: - Activity Log Entry

struct ActivityEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let description: String

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Mock Data

extension SystemStatus {
    static var mock: SystemStatus {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let mockJSON = """
        {
            "hostname": "griffin",
            "uptime": "4d 12h",
            "connection": "local",
            "agents": [
                {
                    "id": "main",
                    "name": "Clawdia",
                    "emoji": "🦞",
                    "role": "Chief of Staff",
                    "status": "active",
                    "activity": "Coordinating agent team, reviewing morning digest",
                    "duration_seconds": 240,
                    "health": "normal",
                    "last_activity": "2026-03-11T14:28:00Z",
                    "channel": "1480700058067533886",
                    "sub_agents": [],
                    "cost": { "session_total": 0.12 }
                },
                {
                    "id": "jony",
                    "name": "Steve",
                    "emoji": "🦞",
                    "role": "Product",
                    "status": "active",
                    "activity": "Writing product spec for ClawView — design review pass",
                    "duration_seconds": 720,
                    "health": "taking_a_while",
                    "last_activity": "2026-03-11T14:25:00Z",
                    "channel": "1480707570179117167",
                    "sub_agents": [
                        { "id": "sub1", "label": "designer-clawview", "status": "running", "duration_seconds": 180 }
                    ],
                    "cost": { "session_total": 0.42 }
                },
                {
                    "id": "dev",
                    "name": "Linus",
                    "emoji": "⚙️",
                    "role": "Engineering",
                    "status": "idle",
                    "activity": "Idle",
                    "duration_seconds": 0,
                    "health": "idle",
                    "last_activity": "2026-03-11T12:10:00Z",
                    "channel": "1480700105781678183",
                    "sub_agents": [],
                    "cost": null
                }
            ]
        }
        """
        let data = mockJSON.data(using: .utf8)!
        var status = try! decoder.decode(SystemStatus.self, from: data)
        return status
    }
}

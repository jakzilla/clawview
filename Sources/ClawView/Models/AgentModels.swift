/**
 * AgentModels.swift
 * -----------------
 * All data models used throughout ClawView.
 *
 * Key types:
 *
 *   AgentInfo       — The core model. One per agent (Clawdia, Linus, Steve, etc.).
 *                     Holds status, current activity text, health, sub-agents, cost.
 *
 *   SystemStatus    — Top-level response from the status server. Contains hostname,
 *                     uptime, and the full agents array. This is what GatewayService
 *                     decodes from /api/clawview/status.
 *
 *   AgentHealth     — Four-state health enum. Derived from "how long since last
 *                     activity in an active session": normal / takingAWhile / stuck / idle.
 *
 *   ActivityType    — How the activity string was determined. Affects rendering:
 *                     agent_reported / tool_call → full opacity, regular weight;
 *                     inferred / stale → reduced opacity, italic.
 *
 *   ConnectionState — Whether we're connected via local network, SSH tunnel,
 *                     disconnected, or in an error state.
 *
 * The file also contains `SystemStatus.mock` — a static mock payload used by
 * ConnectionManager's mock mode for UI development without a live OpenClaw system.
 */

import Foundation

// MARK: - Agent Status Models

enum AgentHealth: String, Codable {
    case normal = "normal"
    case takingAWhile = "taking_a_while"
    case stuck = "stuck"
    case idle = "idle"
}

/// V2 activity source type — used to style activity text
enum ActivityType: String, Codable {
    case agentReported = "agent_reported"  // Agent explicitly set this (gold standard)
    case toolCall = "tool_call"             // Inferred from tool call (reliable)
    case inferred = "inferred"              // Best-effort from text parsing
    case stale = "stale"                    // No activity signal; last known

    /// Opacity to render activity text at
    var opacity: Double {
        switch self {
        case .agentReported: return 1.0
        case .toolCall:      return 1.0
        case .inferred:      return 0.8
        case .stale:         return 0.6
        }
    }

    /// Whether to render in italic
    var isItalic: Bool {
        switch self {
        case .agentReported, .toolCall: return false
        case .inferred, .stale:         return true
        }
    }
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
}

struct AgentCost: Codable {
    let sessionTotal: Double

    enum CodingKeys: String, CodingKey {
        case sessionTotal = "session_total"
    }
}

struct RecentActivityEntry: Identifiable, Codable {
    let id = UUID()
    let time: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case time, text
    }

    var formattedTime: String {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: time) {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            return fmt.string(from: date)
        }
        return time
    }
}

struct AgentInfo: Identifiable, Codable {
    let id: String
    let name: String
    let emoji: String
    let role: String
    let status: String          // "active" | "idle"
    let activity: String
    let activityType: ActivityType?   // V2: how activity text was determined
    let durationSeconds: Int
    let health: AgentHealth
    let lastActivity: Date?
    let channel: String?
    let subAgents: [SubAgentInfo]
    let cost: AgentCost?
    let recentActivity: [RecentActivityEntry]

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, role, status, activity, health, channel, cost
        case activityType = "activity_type"
        case durationSeconds = "duration_seconds"
        case lastActivity = "last_activity"
        case subAgents = "sub_agents"
        case recentActivity = "_recentActivity"
    }

    // Computed helpers
    var isActive: Bool { status == "active" }

    /// Resolved activity type (defaults to .inferred if not provided)
    var resolvedActivityType: ActivityType {
        activityType ?? (isActive ? .inferred : .stale)
    }

    // Fallback init without recentActivity (for migration)
    init(id: String, name: String, emoji: String, role: String, status: String,
         activity: String, activityType: ActivityType? = nil, durationSeconds: Int, health: AgentHealth,
         lastActivity: Date?, channel: String?, subAgents: [SubAgentInfo],
         cost: AgentCost?, recentActivity: [RecentActivityEntry] = []) {
        self.id = id; self.name = name; self.emoji = emoji; self.role = role
        self.status = status; self.activity = activity; self.activityType = activityType
        self.durationSeconds = durationSeconds; self.health = health
        self.lastActivity = lastActivity; self.channel = channel
        self.subAgents = subAgents; self.cost = cost
        self.recentActivity = recentActivity
    }
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

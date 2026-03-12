/**
 * AgentCardView.swift
 * -------------------
 * Renders a single agent as a collapsible card in the popover.
 *
 * Collapsed state (always visible):
 *   [emoji]  Name (Role)
 *            Current activity text  (truncated to 2 lines)
 *            Duration · health dot + label  OR  "Last active Xm ago"
 *            [chevron →]
 *
 * Expanded state (tap the card to toggle):
 *   [Recent Activity]  — last 8 tool calls / activity entries from session JSONL
 *   [Sub-Agents]       — active sub-agent sessions (if any)
 *   [Cost]             — session cost in USD (if available)
 *   [Nudge]            — stub button (v1.1)
 *
 * The expansion animation uses a spring transition on the chevron rotation
 * and an opacity + offset transition on the expanded content.
 *
 * Health color mapping:
 *   normal       → systemGreen
 *   takingAWhile → systemYellow
 *   stuck        → systemRed
 *   idle         → systemGray
 */

import SwiftUI

// MARK: - Agent Card View

struct AgentCardView: View {
    let agent: AgentInfo
    let index: Int

    @State private var isExpanded: Bool = false
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Collapsed header (always visible)
            HStack(alignment: .top, spacing: 10) {
                // Emoji
                Text(agent.emoji)
                    .font(.system(size: 24))
                    .frame(width: 32, height: 32, alignment: .center)

                // Text column
                VStack(alignment: .leading, spacing: 4) {
                    // Name + Role
                    HStack(spacing: 4) {
                        Text(agent.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Text("(\(agent.role))")
                            .font(.headline)
                            .fontWeight(.regular)
                            .foregroundColor(.secondary)
                    }

                    // Activity
                    Text(agent.isActive ? agent.activity : "Idle")
                        .font(.subheadline)
                        .foregroundColor(agent.isActive ? .primary : Color(nsColor: NSColor.tertiaryLabelColor))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Duration + health
                    if agent.isActive || agent.health != .idle {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundColor(Color(nsColor: NSColor.tertiaryLabelColor))

                            Text(formattedDuration)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Color(nsColor: NSColor.tertiaryLabelColor))

                            Text("·")
                                .font(.caption)
                                .foregroundColor(Color(nsColor: NSColor.tertiaryLabelColor))

                            Circle()
                                .fill(healthColor)
                                .frame(width: 6, height: 6)

                            Text(healthLabel)
                                .font(.system(.caption, weight: .medium))
                                .foregroundColor(healthColor)
                        }
                    } else {
                        if let lastActivity = agent.lastActivity {
                            Text("Last active: \(relativeTime(lastActivity))")
                                .font(.caption)
                                .foregroundColor(Color(nsColor: NSColor.tertiaryLabelColor))
                        }
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: NSColor.tertiaryLabelColor))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                isHovered
                    ? Color(nsColor: NSColor.quaternaryLabelColor)
                    : Color.clear
            )
            .contentShape(Rectangle())
            .onHover { hover in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hover
                }
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            }

            // Expanded detail
            if isExpanded {
                ExpandedAgentDetail(agent: agent)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(
                        .opacity.combined(with: .offset(y: -4))
                    )
            }
        }
    }

    // MARK: - Helpers

    private var formattedDuration: String {
        let secs = agent.durationSeconds
        if secs < 60 { return "\(secs)s" }
        let mins = secs / 60
        if mins < 60 { return "\(mins) min" }
        let hours = mins / 60
        let remainingMins = mins % 60
        return remainingMins == 0 ? "\(hours)h" : "\(hours)h \(remainingMins)m"
    }

    private var healthColor: Color {
        switch agent.health {
        case .normal: return Color(nsColor: NSColor.systemGreen)
        case .takingAWhile: return Color(nsColor: NSColor.systemYellow)
        case .stuck: return Color(nsColor: NSColor.systemRed)
        case .idle: return Color(nsColor: NSColor.systemGray)
        }
    }

    private var healthLabel: String {
        switch agent.health {
        case .normal: return "Normal"
        case .takingAWhile: return "Taking a while"
        case .stuck: return "Stuck"
        case .idle: return "Idle"
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(date))
        if elapsed < 60 { return "just now" }
        if elapsed < 3600 { return "\(elapsed / 60)m ago" }
        return "\(elapsed / 3600)h ago"
    }
}

// MARK: - Expanded Agent Detail

struct ExpandedAgentDetail: View {
    let agent: AgentInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Container
            VStack(alignment: .leading, spacing: 12) {

                // Recent Activity from live session data
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeader("RECENT ACTIVITY")
                    Divider()

                    let activities = agent.recentActivity
                    if activities.isEmpty {
                        Text("No recent activity")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: NSColor.tertiaryLabelColor))
                    } else {
                        ForEach(activities) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.formattedTime)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(Color(nsColor: NSColor.tertiaryLabelColor))
                                    .frame(width: 40, alignment: .leading)

                                Text(entry.text)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                // Sub-agents
                if !agent.subAgents.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionHeader("SUB-AGENTS")
                        Divider()

                        ForEach(agent.subAgents) { sub in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(nsColor: NSColor.systemGreen))
                                    .frame(width: 6, height: 6)
                                Text(sub.label)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatDuration(sub.durationSeconds))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(Color(nsColor: NSColor.tertiaryLabelColor))
                            }
                        }
                    }
                }

                // Cost
                if let cost = agent.cost {
                    HStack {
                        Text("Cost: $\(String(format: "%.2f", cost.sessionTotal))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }

                // Nudge button
                Button("Nudge") {
                    // v1.1 feature
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .font(.system(.caption, weight: .medium))
                .frame(height: 24)
                .disabled(true) // Coming in v1.1
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: NSColor.quaternarySystemFill))
            )
        }
        .animation(.easeOut(duration: 0.2).delay(0.05), value: true)
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
    }

    private func formatDuration(_ secs: Int) -> String {
        if secs < 60 { return "\(secs)s" }
        return "\(secs / 60) min"
    }
}

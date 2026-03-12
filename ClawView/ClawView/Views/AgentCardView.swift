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
                        .foregroundColor(agent.isActive ? .primary : Color(NSColor.tertiaryLabelColor))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Duration + health
                    if agent.isActive || agent.health != .idle {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))

                            Text(formattedDuration)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))

                            Text("·")
                                .font(.caption)
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))

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
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        }
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                isHovered
                    ? Color(NSColor.quaternaryLabelColor)
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
        return "\(hours)h \(mins % 60)m"
    }

    private var healthColor: Color {
        switch agent.health {
        case .normal: return Color(NSColor.systemGreen)
        case .takingAWhile: return Color(NSColor.systemYellow)
        case .stuck: return Color(NSColor.systemRed)
        case .idle: return Color(NSColor.systemGray)
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

                // Recent Activity — wired to real _recentActivity from Gateway API (#2)
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeader("RECENT ACTIVITY")
                    Divider()

                    if agent.recentActivity.isEmpty {
                        Text("No recent activity")
                            .font(.caption)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    } else {
                        // Show up to 8 entries, most recent last
                        ForEach(agent.recentActivity.suffix(8)) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.formattedTime)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
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
                                    .fill(Color(NSColor.systemGreen))
                                    .frame(width: 6, height: 6)
                                Text(sub.label)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatDuration(sub.durationSeconds))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
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
                    .fill(Color(NSColor.quaternarySystemFill))
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

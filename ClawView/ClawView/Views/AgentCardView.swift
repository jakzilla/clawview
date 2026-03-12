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
                VStack(alignment: .leading, spacing: 2) {
                    // Name — headline only. Role is shown as subordinate caption (#13)
                    Text(agent.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    // Role — small caption below name, not in parentheses (#13)
                    Text(agent.role)
                        .font(.caption)
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))

                    // Activity — use sanitised text to avoid emoji causing line-height variance (#41)
                    Text(agent.isActive ? displayActivity : "Idle")
                        .font(.subheadline)
                        .foregroundColor(agent.isActive ? .primary : Color(NSColor.tertiaryLabelColor))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)

                    // Duration row — only for active agents with meaningful duration (#9, #15)
                    // Idle agents: show "Last active X ago" instead
                    if agent.isActive && agent.durationSeconds > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))

                            Text(formattedDuration)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))

                            // Health indicator — only for non-normal states (#14)
                            // "Normal" adds no signal; silence IS the signal when healthy
                            if agent.health != .normal && agent.health != .idle {
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
                        }
                    } else if !agent.isActive {
                        if let lastActivity = agent.lastActivity {
                            Text("Last active \(relativeTime(lastActivity))")
                                .font(.caption)
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        }
                    }
                }

                Spacer()

                // Chevron — visual only; the card HStack uses accessibilityElement(children: .ignore)
                // so VoiceOver reads the combined card label instead of individual children (#39).
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
                    .accessibilityHidden(true)
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
            // Combined accessibility element for VoiceOver (#39):
            // reads name, role, and current activity/status as a single unit,
            // then announces the expand/collapse action
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(agent.name), \(agent.role). \(agent.isActive ? agent.activity : "Idle")")
            .accessibilityHint(isExpanded ? "Tap to collapse details" : "Tap to expand details")
            .accessibilityAddTraits(.isButton)

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

    /// Activity text sanitised for display (#41).
    ///
    /// Strips trailing emoji from activity strings. Emoji in body text renders at a
    /// different line metric than surrounding text (larger ascender), causing the
    /// activity row to be taller than adjacent rows — breaking visual alignment.
    ///
    /// Matches Unicode emoji ranges including variation selectors and ZWJ sequences
    /// via a regex on the trailing portion of the string.
    private var displayActivity: String {
        agent.activity
            .trimmingCharacters(in: .whitespaces)
            // Strip trailing emoji (including variation selectors U+FE0F, ZWJ U+200D,
            // and common emoji ranges U+1F000–1FFFF and U+2600–27FF)
            .replacingOccurrences(
                of: #"\s*[\u{1F000}-\u{1FFFF}\u{2600}-\u{27FF}\u{FE00}-\u{FE0F}\u{200D}]+\s*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespaces)
    }

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
        case .normal: return ""   // Not shown (#14)
        case .takingAWhile: return "Taking a while"
        case .stuck: return "Stuck"
        case .idle: return ""     // Not shown
        }
    }

    /// Cached DateFormatter for the ≥7-day branch of relativeTime.
    /// Static to avoid recreating the expensive object on every call (#31).
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// Returns a human-readable relative time string for display in agent cards (#31).
    ///
    /// Scale:
    ///   < 60s      → "just now"
    ///   < 60m      → "Xm ago"
    ///   < 24h      → "Xh ago"
    ///   1 day      → "yesterday"
    ///   < 7 days   → "X days ago"
    ///   ≥ 7 days   → "MMM d" (e.g. "Mar 10")
    private func relativeTime(_ date: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(date))
        if elapsed < 60 { return "just now" }
        if elapsed < 3600 { return "\(elapsed / 60)m ago" }
        if elapsed < 86400 { return "\(elapsed / 3600)h ago" }
        let days = elapsed / 86400
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }
        return AgentCardView.shortDateFormatter.string(from: date)
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

                    if agent.filteredRecentActivity.isEmpty {
                        Text("No recent activity")
                            .font(.caption)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    } else {
                        ForEach(agent.filteredRecentActivity.suffix(8)) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.formattedTime)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                                    // Width 72: fits "Yest HH:mm" (9 chars) and "MMM d HH:mm" (11 chars) (#32)
                                    .frame(width: 72, alignment: .leading)

                                // cleanedText is non-nil for every entry in filteredRecentActivity
                                Text(entry.cleanedText ?? entry.text)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                // Sub-agents — with proper status colours and identity (#5)
                if !agent.subAgents.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionHeader("SUB-AGENTS")
                        Divider()

                        ForEach(Array(agent.subAgents.enumerated()), id: \.element.id) { index, sub in
                            HStack(spacing: 6) {
                                // Dot colour reflects actual status — not hardcoded green (#5)
                                Circle()
                                    .fill(subAgentStatusColor(sub.status))
                                    .frame(width: 6, height: 6)
                                    .accessibilityHidden(true)  // label text conveys status (#39)

                                // Label: use API label if it has real content; otherwise
                                // fall back to "Sub-agent N" with ordinal (#27).
                                // The ordinal makes multiple anonymous sub-agents distinguishable
                                // until the Gateway emits task-derived labels.
                                let displayLabel: String = {
                                    let raw = sub.label.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let isGeneric = raw.isEmpty || raw.lowercased() == "sub-agent"
                                    if isGeneric {
                                        return "Sub-agent \(index + 1)"
                                    }
                                    // Capitalise first letter for display consistency
                                    return raw.prefix(1).uppercased() + raw.dropFirst()
                                }()

                                Text(displayLabel)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                // Duration only meaningful for active sub-agents (#5)
                                if sub.status == "active" {
                                    Text(formatDuration(sub.durationSeconds))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                                } else {
                                    Text("done")
                                        .font(.caption)
                                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                                }
                            }
                        }
                    }
                }

                // Cost — only shown if non-zero and meaningful (#4)
                // $0.00 means "not tracked", not "free" — hide it
                if let cost = agent.cost, cost.sessionTotal > 0.001 {
                    HStack {
                        Image(systemName: "dollarsign.circle")
                            .font(.system(size: 10))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Text("$\(String(format: "%.2f", cost.sessionTotal)) this session")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }

                // Nudge button removed — disabled UI is a broken promise (#7)
                // Will be re-added in v1.1 when Gateway routing is implemented
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.quaternarySystemFill))
            )
        }
        // Fixed: was `.animation(..., value: true)` — constant never changes so animation never fires (#18)
        // Now driven by the parent's isExpanded toggle, which passes through via re-render.
        // The transition on the `if isExpanded` block in AgentCardView handles the actual animation.
        // This modifier is removed to avoid the dead animation conflicting with the spring transition.
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
    }

    /// Sub-agent status → dot colour (#5)
    private func subAgentStatusColor(_ status: String) -> Color {
        switch status {
        case "active":  return Color(NSColor.systemGreen)
        case "error":   return Color(NSColor.systemRed)
        default:        return Color(NSColor.systemGray)  // idle, done, unknown
        }
    }

    private func formatDuration(_ secs: Int) -> String {
        if secs < 60 { return "\(secs)s" }
        return "\(secs / 60) min"
    }
}

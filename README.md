# ClawView 🦞

**A native macOS menu bar app that gives you ambient awareness of your [OpenClaw](https://github.com/jakzilla/openclaw) agent system.**

Glance at the icon → know if your agents are working. Click it → see exactly what each one is doing.

---

## Screenshots

> 📸 Screenshots coming soon — the app is running, photos are on their way.

---

## How it works

ClawView is a thin, always-on observer. It never talks directly to agents or the OpenClaw gateway. Instead:

```
ClawView.app  (Swift / AppKit + SwiftUI)
     │
     │  HTTP poll every 5s
     ▼
clawview-status-server.js  (Node.js, localhost:7317)
     │
     │  reads session files directly
     ▼
~/.openclaw/agents/*/sessions/
```

1. **The status server** runs locally as a LaunchAgent. It parses OpenClaw's session JSONL files — reading the last 32 KB of each active session to extract what each agent is currently doing, then exposes that as a clean JSON API.

2. **The Swift app** polls `/api/clawview/status` every 5 seconds and updates the menu bar icon and popover reactively. No persistent connection, no WebSocket complexity — just reliable HTTP polling.

3. **Activity inference** happens in the status server: tool calls (e.g. `read`, `exec`, `web_search`) are translated into human-readable strings ("Reading SPEC.md", "Running command"). Raw assistant text is only used if it clearly describes work, never conversation.

---

## Menu bar icon states

| Icon state | Meaning |
|---|---|
| 🐜 solid | Connected, all agents idle |
| 🐜 pulsing | One or more agents actively working |
| 🐜 + yellow dot | Agent taking longer than expected |
| 🐜 + red dot | Agent appears stuck (>10 min silent) |
| 🐜 dimmed | Cannot reach status server |

---

## Requirements

- **macOS 14 (Sonoma)** or later
- **[OpenClaw](https://github.com/jakzilla/openclaw)** installed and running on the same machine (or reachable on your local network)
- **Node.js 18+** (for the status server)
- **Swift 5.9+** (to build from source)

---

## Installation

### 1. Clone the repo

```bash
git clone https://github.com/jakzilla/clawview.git
cd clawview
```

### 2. Build the app

```bash
bash build.sh
```

This compiles the Swift package and assembles a proper `.app` bundle in the project directory.

### 3. Move to Applications (optional)

```bash
cp -r ClawView.app /Applications/
```

### 4. Start the status server

The status server reads your OpenClaw session files and serves them to the app:

```bash
node clawview-status-server.js
```

To run it automatically at login, install it as a LaunchAgent:

```bash
# Create the plist
cat > ~/Library/LaunchAgents/com.openclaw.clawview-status.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.clawview-status</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/node</string>
        <string>/path/to/clawview/clawview-status-server.js</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/clawview-status.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/clawview-status.log</string>
</dict>
</plist>
EOF

# Load it
launchctl load ~/Library/LaunchAgents/com.openclaw.clawview-status.plist
```

### 5. Launch ClawView

```bash
open ClawView.app
# or double-click it in Finder
```

On first run, a setup screen guides you through connecting to the status server. If you're running everything on the same Mac, the defaults (`localhost:7317`) work out of the box.

---

## Verifying it's working

```bash
# Check the status server is up
curl http://127.0.0.1:7317/health
# → {"ok":true,"version":2}

# Check agent data is flowing
curl http://127.0.0.1:7317/api/clawview/status | jq '.agents[].name'

# View server logs
tail -f /tmp/clawview-status.log
```

---

## Development

### Build from source

```bash
# Debug build (fast, no optimisations)
swift build

# Run tests (if any)
swift test

# Use build.sh to produce a runnable .app bundle
bash build.sh
open ClawView.app
```

### Mock mode

The app has a built-in mock data mode — useful for working on the UI without a running OpenClaw system. Enable it via **Settings → Use mock data**. Mock data shows three agents (Clawdia, Steve, Linus) in various states.

### Status server development

The status server is a single self-contained Node.js script — no dependencies, no build step:

```bash
node clawview-status-server.js
```

It includes a port-reuse guard: if already running, a new invocation will detect it and exit cleanly.

#### API endpoints

| Endpoint | Description |
|---|---|
| `GET /api/clawview/status` | Primary endpoint — full agent list in V1 schema |
| `GET /api/sessions/active` | V2 schema (richer fields, future-facing) |
| `GET /api/status` | Gateway health check |
| `GET /health` | Server health check |
| `POST /api/sessions/:id/nudge` | Stub — nudge routing (not yet wired to gateway) |

---

## Project structure

```
clawview/
│
├── Sources/ClawView/
│   │
│   ├── ClawViewApp.swift          — App entry point, NSApplicationDelegate,
│   │                                menu bar setup, popover lifecycle,
│   │                                launch-at-login (SMAppService)
│   │
│   ├── Models/
│   │   └── AgentModels.swift      — All data models: AgentInfo, SystemStatus,
│   │                                AgentHealth, ActivityType, ConnectionState,
│   │                                SubAgentInfo, mock data
│   │
│   ├── Services/
│   │   ├── GatewayService.swift   — HTTP polling loop (5s), response parsing,
│   │   │                            fallback from /api/clawview/status → /api/sessions,
│   │   │                            computed properties (activeAgents, hasStuckAgents…)
│   │   ├── ConnectionManager.swift — Persists connection settings to UserDefaults,
│   │   │                             first-run detection, mock mode
│   │   └── BonjourDiscovery.swift  — mDNS browser for _openclaw._tcp service,
│   │                                 auto-discovers Mac mini on local network
│   │
│   └── Views/
│       ├── PopoverView.swift       — Root popover: routes between FirstRun / Settings
│       │                             / main content. Header (hostname + heartbeat),
│       │                             footer (Discord / Processes / Settings buttons),
│       │                             disconnected state view
│       ├── AgentCardView.swift     — Collapsed + expanded agent cards. Tap to expand.
│       │                             Shows: emoji, name, role, activity text, duration,
│       │                             health indicator, recent activity log, sub-agents,
│       │                             cost, nudge button (stub)
│       ├── SettingsView.swift      — Settings panel + first-run onboarding screen
│       │                             with Bonjour host discovery
│       └── MenuBarIconView.swift   — NSStatusItem lifecycle, 5 icon states,
│                                     Core Animation opacity pulse (for "working"),
│                                     CALayer badge (yellow/red dot for warnings)
│
├── clawview-status-server.js       — Local status API server (Node.js, no deps).
│                                     Reads ~/.openclaw/agents/*/sessions/ JSONL files,
│                                     humanises tool calls, infers activity text,
│                                     exposes V1 + V2 JSON API on localhost:7317
│
├── Package.swift                   — Swift Package manifest (macOS 14+, SwiftUI)
├── build.sh                        — Compiles with `swift build` and assembles .app bundle
├── .gitignore                      — Excludes .build/, *.app, DerivedData, etc.
└── LICENSE                         — MIT
```

---

## Activity text: how it works

One of the trickier parts is surfacing *what an agent is actually doing* rather than what it's saying. The status server uses a layered approach:

1. **Agent-reported** (future): agents can write a `.status` file to `~/.openclaw/agents/<id>/`. Not yet widely used, but the infra is there.
2. **Tool call** (primary): the last tool call in the session JSONL is humanised — `read(path: "SPEC.md")` → "Reading SPEC.md", `exec(command: "swift build")` → "Running command".
3. **Inferred** (fallback): if the last assistant message starts with a gerund ("Reading...", "Building...", "Checking..."), it's used as-is. Conversational text is discarded.
4. **Stale**: nothing recent → shows "Idle — last active Xm ago".

Activity type is passed through to the Swift app, which renders inferred/stale text in italics at reduced opacity.

---

## Health states

| State | Condition | Display |
|---|---|---|
| **Normal** | Activity within last 2 minutes | Green dot |
| **Taking a while** | Active session, last activity 2–10 min ago | Yellow dot |
| **Stuck** | Active session, no activity for >10 min | Red dot |
| **Idle** | No session activity in the last 30 minutes | Grey dot |

---

## Roadmap

- [ ] WebSocket push from status server (replace polling)
- [ ] "Nudge" button — send a message to an agent from the popover
- [ ] macOS notifications for stuck agents
- [ ] SSH tunnel mode (connect to a remote OpenClaw host)
- [ ] Session cost display (accurate token cost from JSONL usage entries)
- [ ] Launch at Login toggle in Settings UI

---

## License

MIT — see [LICENSE](LICENSE).

Built with 🦞 by the OpenClaw project.

# LaunchAgents

LaunchAgent plists for ClawView services. Install by copying to `~/Library/LaunchAgents/` and loading with `launchctl load`.

## Files

| Plist | Port | Description |
|-------|------|-------------|
| `com.openclaw.clawview-status.plist` | 7317 | ClawView status server (node) |
| `com.openclaw.cloudflared-clawview.plist` | 9876 | Cloudflared tunnel for external status access |
| `com.openclaw.github-webhook-relay.plist` | — | GitHub webhook → Discord relay |

## Install

```bash
cp launchagents/*.plist ~/Library/LaunchAgents/

# Edit webhook relay plist to add real tokens before loading
nano ~/Library/LaunchAgents/com.openclaw.github-webhook-relay.plist

# Load all
launchctl load ~/Library/LaunchAgents/com.openclaw.clawview-status.plist
launchctl load ~/Library/LaunchAgents/com.openclaw.cloudflared-clawview.plist
launchctl load ~/Library/LaunchAgents/com.openclaw.github-webhook-relay.plist
```

## Volume path

All paths reference `/Volumes/Storage/` — ensure the external SSD is mounted at that path.
If the volume name changes, update the `ProgramArguments` paths accordingly.

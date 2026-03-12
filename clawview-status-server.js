#!/usr/bin/env node
/**
 * ClawView Status Server — V2
 * Serves the V2 API schema required by ClawView.
 *
 * Endpoints:
 *   GET /api/status               — Gateway health
 *   GET /api/sessions/active      — V2 agent list (primary data source for ClawView)
 *   GET /api/clawview/status      — Legacy V1 shape (for backward compat with installed app)
 *   GET /health                   — Process health check
 *
 * Run: node clawview-status-server.js
 * Listens on: http://localhost:7317
 */

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const PORT = 7317;
const AGENTS_DIR = path.join(os.homedir(), '.openclaw', 'agents');

// ─── Agent metadata ─────────────────────────────────────────────────────────

const AGENT_META = {
  main:      { name: 'Clawdia', emoji: '🦞', role: 'Chief of Staff',   channel: '1480700058067533886' },
  dev:       { name: 'Linus',   emoji: '⚙️',  role: 'Engineering',      channel: '1480700105781678183' },
  jony:      { name: 'Steve',   emoji: '🦞', role: 'Product',           channel: '1480707570179117167' },
  marketing: { name: 'Richard', emoji: '📣', role: 'Marketing',         channel: '1480700088245424138' },
  research:  { name: 'Demis',   emoji: '🔬', role: 'Research',          channel: '1480700259285074033' },
  pa:        { name: 'Prawn',   emoji: '🎩', role: 'Personal Asst',     channel: '1480700131002159247' },
  intake:    { name: 'Santa',   emoji: '🎅', role: 'Intake',            channel: '1480700154800767037' },
};

// ─── Thresholds ──────────────────────────────────────────────────────────────

// An agent is "active" (not just idle) if its last session activity was within this window
const ACTIVE_WINDOW_MS        = 30 * 60 * 1000;  // 30 minutes
// Within an active session, flag as "stuck" if silent for this long
const STUCK_THRESHOLD_MS      = 10 * 60 * 1000;  // 10 minutes (per spec)
// If idle for more than this, show generic idle text rather than last message
const IDLE_TEXT_THRESHOLD_MS  = 60 * 60 * 1000;  // 1 hour

// ─── Tool call → human text ──────────────────────────────────────────────────

/**
 * Humanise a tool call name + arguments into a plain-English activity string.
 * Never returns raw tool names, file paths, or technical strings.
 */
function humaniseToolCall(name, args) {
  // args may be an object or undefined
  const a = args || {};

  switch (name) {
    // File operations
    case 'read': {
      const p = a.path || a.file_path || '';
      const fname = p ? path.basename(p) : '';
      return fname ? `Reading ${fname}` : 'Reading file';
    }
    case 'write': {
      const p = a.path || a.file_path || '';
      const fname = p ? path.basename(p) : '';
      return fname ? `Writing ${fname}` : 'Writing file';
    }
    case 'edit': {
      const p = a.path || a.file_path || '';
      const fname = p ? path.basename(p) : '';
      return fname ? `Editing ${fname}` : 'Editing file';
    }

    // Shell / exec
    case 'exec':
    case 'bash':
    case 'shell': {
      const cmd = (a.command || '').trim();
      if (!cmd) return 'Running command';

      // Strip cd prefix (cd /path && actual-command)
      const withoutCd = cmd.replace(/^cd\s+\S+\s*&&\s*/, '').trim();
      // Strip env var prefix (VARNAME=value command)
      const withoutEnv = withoutCd.replace(/^(?:[A-Z_]+=\S+\s+)+/, '').trim();
      const effective = withoutEnv || withoutCd || cmd;
      const firstWord = effective.split(/\s+/)[0];
      const restWords = effective.split(/\s+/).slice(1, 4).join(' ');

      // git operations — extract the subcommand
      if (firstWord === 'git') {
        const sub = effective.split(/\s+/)[1] || '';
        const gitMap = {
          commit:   'Committing changes',
          push:     'Pushing to GitHub',
          pull:     'Pulling from remote',
          checkout: 'Switching branch',
          merge:    'Merging branch',
          clone:    'Cloning repo',
          fetch:    'Fetching updates',
          status:   'Checking git status',
          log:      'Reviewing git log',
          add:      'Staging changes',
          diff:     'Reviewing diff',
          branch:   'Managing branches',
          rebase:   'Rebasing branch',
        };
        return gitMap[sub] || 'Running git';
      }

      // Build / compile
      if (firstWord === 'xcodebuild') return 'Building Xcode project';
      if (firstWord === 'swift') return 'Building Swift';
      if (firstWord === 'cargo') return 'Building Rust';
      if (firstWord === 'make') return 'Building project';
      if (firstWord === 'gcc' || firstWord === 'clang') return 'Compiling code';

      // Package managers
      if (firstWord === 'npm') {
        const sub = effective.split(/\s+/)[1] || '';
        return sub === 'install' ? 'Installing packages' : sub === 'run' ? 'Running npm script' : 'Running npm';
      }
      if (firstWord === 'yarn') return 'Running yarn';
      if (firstWord === 'pip' || firstWord === 'pip3') return 'Installing Python package';
      if (firstWord === 'brew') return 'Running brew';
      if (firstWord === 'apt' || firstWord === 'apt-get') return 'Installing package';

      // Scripts
      if (firstWord === 'node') return 'Running Node.js script';
      if (firstWord === 'python' || firstWord === 'python3') return 'Running Python script';
      if (firstWord === 'bash' || firstWord === 'sh') return 'Running shell script';
      if (firstWord === 'ruby') return 'Running Ruby script';

      // Network / HTTP
      if (firstWord === 'curl') {
        // Try to extract a meaningful URL or endpoint
        const urlMatch = effective.match(/https?:\/\/[^\s"']+/);
        if (urlMatch) {
          try {
            const u = new URL(urlMatch[0]);
            return `Fetching ${u.hostname}${u.pathname.slice(0, 30)}`;
          } catch (e) {}
        }
        return 'Fetching URL';
      }
      if (firstWord === 'wget') return 'Downloading file';
      if (firstWord === 'gh') {
        // GitHub CLI — extract subcommand
        const parts = effective.split(/\s+/);
        const sub = parts[1] || '';
        const sub2 = parts[2] || '';
        const ghMap = {
          'pr create':  'Opening pull request',
          'pr merge':   'Merging pull request',
          'pr comment': 'Commenting on PR',
          'pr diff':    'Reviewing PR diff',
          'pr view':    'Viewing pull request',
          'issue list': 'Listing issues',
          'issue view': 'Viewing issue',
        };
        return ghMap[`${sub} ${sub2}`] || ghMap[sub] || 'Running gh';
      }

      // File operations
      if (firstWord === 'cp') return 'Copying files';
      if (firstWord === 'mv') return 'Moving files';
      if (firstWord === 'rm' || firstWord === 'trash') return 'Removing files';
      if (firstWord === 'mkdir') return 'Creating directory';
      if (firstWord === 'ls' || firstWord === 'find') return 'Listing files';
      if (firstWord === 'cat' || firstWord === 'head' || firstWord === 'tail') return 'Reading file';
      if (firstWord === 'grep' || firstWord === 'rg') return 'Searching files';
      if (firstWord === 'open') return 'Opening application';

      // System
      if (firstWord === 'osascript') return 'Running AppleScript';
      if (firstWord === 'launchctl') return 'Managing launch agent';
      if (firstWord === 'pgrep' || firstWord === 'ps') return 'Checking processes';
      if (firstWord === 'kill' || firstWord === 'pkill') return 'Stopping process';

      // If it's a short command we don't recognise, show it trimmed
      if (firstWord.length > 0 && firstWord.length <= 20 && /^[a-z]/.test(firstWord)) {
        return `Running ${firstWord}`;
      }

      return 'Running command';
    }

    // Web / search
    case 'web_search':
    case 'search':
    case 'brave_search': {
      const q = a.query || a.q || '';
      return q ? `Searching: ${q.slice(0, 40)}` : 'Searching the web';
    }

    // Messaging
    case 'message':
    case 'send_message':
    case 'discord_message': {
      return 'Sending message';
    }

    // Sub-agents
    case 'sessions_spawn':
    case 'subagents_spawn':
    case 'spawn': {
      const task = a.task || '';
      if (!task) return 'Spawning sub-agent';
      // Extract a clean label from "You are X..." or "Task: X..."
      const youAreMatch = task.match(/You are ([^,\.]+)/i);
      const taskMatch = task.match(/[Tt]ask:\s*([^.]+)/);
      if (youAreMatch) return `Delegating to ${youAreMatch[1].trim().slice(0, 40)}`;
      if (taskMatch) return `Spawning: ${taskMatch[1].trim().slice(0, 40)}`;
      return 'Spawning sub-agent';
    }

    // Memory / notes
    case 'apple_notes':
    case 'memo':
    case 'obsidian': {
      return 'Taking notes';
    }

    // Process management
    case 'process': {
      return 'Managing process';
    }

    // Catch-all — never show the raw tool name
    default:
      return 'Working...';
  }
}

// ─── Activity text cleaner ───────────────────────────────────────────────────

/**
 * Take raw assistant text and return a clean, human-readable activity string,
 * but ONLY if it reads like "what I'm doing" not "what I'm saying to Jack".
 *
 * We want: "Reading SPEC.md", "Writing the summary", "Checking the API"
 * We don't want: "Honestly, I can't fully guarantee it right now..."
 * We don't want: "Let me check that for you..."
 *
 * Returns null if the text is conversational (should fall back to tool_call or "Thinking...")
 */
function cleanActivityText(raw) {
  if (!raw || typeof raw !== 'string') return null;

  let text = raw
    .replace(/\[\[.*?\]\]/g, '')            // strip [[reply_to_current]] etc
    .replace(/```[\s\S]*?```/g, '')         // strip code blocks
    .replace(/`[^`]+`/g, (m) => m.slice(1, -1).replace(/[/\\]/g, '').trim())
    .replace(/\*\*(.*?)\*\*/g, '$1')
    .replace(/\*(.*?)\*/g, '$1')
    .replace(/#{1,6}\s/g, '')
    .replace(/\n+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  // Drop if it looks like JSON, file path, or technical output
  if (text.startsWith('{') || text.startsWith('[') || text.startsWith('/')) return null;
  if (text.length < 5) return null;

  // ── Strategy: only accept text that clearly describes work being done ──
  //
  // The challenge: agents produce two types of assistant messages:
  // 1. WORK descriptions: "Reading file.md", "Building the API", "Running command"
  // 2. CONVERSATION: "Linus is on it!", "Let me check that...", "Done — committed."
  //
  // For ClawView, we only want (1). If we can't get a clean work description,
  // we fall through to "Thinking..." rather than show a chat excerpt.
  //
  // Rule: Accept ONLY if text starts with a present-tense action verb (gerund).
  // Everything else is conversation → return null → caller uses "Thinking..."

  const actionVerbPattern = /^(reading|writing|running|building|checking|reviewing|updating|creating|editing|spawning|fetching|searching|analysing|analyzing|deploying|testing|fixing|refactoring|installing|configuring|loading|processing|parsing|generating|compiling|linking|downloading|uploading|scanning|auditing|committing|pushing|pulling|cloning)/i;

  if (!actionVerbPattern.test(text)) return null;

  return text.slice(0, 100).trim();
}

// ─── Session file parser ──────────────────────────────────────────────────────

/**
 * Parse recent entries from a session JSONL file.
 * Returns { lastActivity, activityText, activityType, activitySinceMs, recentEntries, subAgents, sessionStartedAt, cost }
 */
function parseSessionFile(sessionFile) {
  const result = {
    lastActivityMs: 0,
    activityText: null,
    activityType: 'stale',   // agent_reported | tool_call | inferred | stale
    activitySinceMs: 0,
    recentEntries: [],
    subAgents: [],
    sessionStartedAt: null,
    cost: null,
  };

  if (!sessionFile || !fs.existsSync(sessionFile)) return result;

  try {
    const stat = fs.statSync(sessionFile);
    const readSize = Math.min(stat.size, 32768); // last 32KB
    const buf = Buffer.alloc(readSize);
    const fd = fs.openSync(sessionFile, 'r');
    fs.readSync(fd, buf, 0, readSize, stat.size - readSize);
    fs.closeSync(fd);

    const lines = buf.toString('utf8').split('\n').filter(l => l.trim());

    // Also get the first line for session start time
    if (stat.size > readSize) {
      try {
        const startBuf = Buffer.alloc(512);
        const sfd = fs.openSync(sessionFile, 'r');
        const bytesRead = fs.readSync(sfd, startBuf, 0, 512, 0);
        fs.closeSync(sfd);
        const firstLine = startBuf.slice(0, bytesRead).toString('utf8').split('\n')[0];
        const firstEntry = JSON.parse(firstLine);
        if (firstEntry.timestamp) {
          result.sessionStartedAt = new Date(firstEntry.timestamp).toISOString();
        }
      } catch (e) {}
    }

    // Parse lines from most recent to find last activity
    // We want: last assistant text, last tool call, cost from last usage entry
    let foundActivity = false;
    const now = Date.now();
    const ENTRY_WINDOW_MS = 24 * 60 * 60 * 1000; // look back 24h for recent entries

    for (let i = lines.length - 1; i >= 0; i--) {
      let entry;
      try {
        entry = JSON.parse(lines[i]);
      } catch (e) {
        continue;
      }

      const ts = entry.timestamp ? new Date(entry.timestamp).getTime() : 0;

      // Grab session start from first valid entry if we haven't already
      if (!result.sessionStartedAt && ts > 0) {
        // Not the start — we'd need the first line for that
        // Leave null if we couldn't get it from the file start
      }

      if (entry.type !== 'message') continue;

      const msg = entry.message || {};
      const role = msg.role;

      if (role === 'assistant') {
        const content = msg.content;
        const usage = msg.usage;

        // Extract cost from usage
        if (!result.cost && usage && usage.cost) {
          const total = usage.cost.total;
          if (typeof total === 'number') {
            result.cost = total;
          }
        }

        if (!Array.isArray(content)) continue;

        // In a single assistant message, prefer tool_calls over text for activity
        // We scan the whole content array first to find if there's a tool call
        let messageToolCall = null;
        let messageText = null;
        for (const c of content) {
          if ((c.type === 'toolCall' || c.type === 'tool_use') && !messageToolCall) {
            const toolName = c.name || c.toolName || '';
            const toolArgs = c.arguments || c.input || {};
            messageToolCall = humaniseToolCall(toolName, toolArgs);
          } else if (c.type === 'text' && c.text && !messageText) {
            messageText = cleanActivityText(c.text);
          }
        }

        // For the activity text: prefer meaningful assistant text > tool call > fallback
        // Assistant text often has better context ("Reading SPEC.md", "Reviewing PR diff")
        // than a raw tool call label. But only if it passes the action-verb filter.
        if (!foundActivity) {
          if (messageText) {
            // Meaningful text beats a generic tool call like "Running command"
            result.activityText = messageText;
            result.activityType = 'inferred';
            result.lastActivityMs = ts || now;
            foundActivity = true;
          } else if (messageToolCall) {
            result.activityText = messageToolCall;
            result.activityType = 'tool_call';
            result.lastActivityMs = ts || now;
            foundActivity = true;
          }
        }

        // Build recent activity entries (last 8, within 24h window)
        // For entries: prefer tool call text (more granular) over assistant narration
        if (ts > 0 && (now - ts) < ENTRY_WINDOW_MS) {
          const entryText = messageToolCall || messageText;
          if (entryText && result.recentEntries.length < 8) {
            result.recentEntries.unshift({
              time: new Date(ts).toISOString(),
              text: entryText,
            });
          }
        }

        // Set sessionStartedAt from first-pass scan (we're going backwards so last one wins = earliest)
        if (ts > 0 && (!result.sessionStartedAt || ts < new Date(result.sessionStartedAt).getTime())) {
          result.sessionStartedAt = new Date(ts).toISOString();
        }
      }

      // Stop if we have everything we need
      if (foundActivity && result.recentEntries.length >= 8) break;
    }

    // Calculate activity_since (how long the current activity has been showing)
    if (result.lastActivityMs > 0) {
      result.activitySinceMs = Date.now() - result.lastActivityMs;
    }

    // Cap recent entries at 8
    result.recentEntries = result.recentEntries.slice(-8);

  } catch (e) {
    // Ignore parse errors
  }

  return result;
}

// ─── Per-agent status builder ─────────────────────────────────────────────────

function getAgentStatusV2(agentId) {
  const meta = AGENT_META[agentId] || { name: agentId, emoji: '🤖', role: 'Agent', channel: null };
  const agentDir = path.join(AGENTS_DIR, agentId);
  const sessionsFile = path.join(agentDir, 'sessions', 'sessions.json');

  if (!fs.existsSync(sessionsFile)) return null;

  let sessions;
  try {
    sessions = JSON.parse(fs.readFileSync(sessionsFile, 'utf8'));
  } catch (e) {
    return null;
  }

  // Find the most recent non-subagent, non-cron main session
  let bestKey = null;
  let bestSession = null;
  let bestUpdatedAt = 0;

  for (const [key, session] of Object.entries(sessions)) {
    // Skip subagent and cron sessions
    if (key.includes('subagent') || key.includes('cron')) continue;
    const updatedAt = session.updatedAt || 0;
    if (updatedAt > bestUpdatedAt) {
      bestUpdatedAt = updatedAt;
      bestSession = session;
      bestKey = key;
    }
  }

  if (!bestSession || !bestKey) return null;

  const now = Date.now();
  const sessionAgeMsFromUpdatedAt = now - bestUpdatedAt;

  // Parse the session file for detailed activity
  const parsed = parseSessionFile(bestSession.sessionFile);

  // Use the more recent of: session updatedAt vs parsed lastActivityMs
  const lastActivityMs = Math.max(
    bestUpdatedAt,
    parsed.lastActivityMs || 0
  );
  const activityAgeMs = now - lastActivityMs;

  // ── Status determination ──────────────────────────────────────────────────
  // "active" = had meaningful session activity within the active window
  //            AND we have actual content (tool calls or text) to show
  // "idle"   = no recent activity OR no parseable content
  //
  // Key: we do NOT mark an idle agent as "stuck". Stuck only applies to agents
  // that WERE active recently and have now gone silent unexpectedly.
  //
  // An agent with updatedAt within 30 min but NO parseable content (empty session)
  // is still shown as idle — it has a session but hasn't done anything meaningful.

  const wasRecentlyActive = activityAgeMs < ACTIVE_WINDOW_MS;
  // Require that we actually have parseable activity content to show "active"
  const hasParseableActivity = parsed.lastActivityMs > 0 && parsed.activityText != null;
  const status = (wasRecentlyActive && hasParseableActivity) ? 'active' : 'idle';

  // Health — only "stuck" if agent was active AND has gone suspiciously quiet
  let health = 'normal';
  if (!wasRecentlyActive) {
    health = 'idle';
  } else if (activityAgeMs > STUCK_THRESHOLD_MS) {
    health = 'stuck';
  } else {
    health = 'normal';
  }

  // ── Activity text ──────────────────────────────────────────────────────────
  // Priority:
  // 1. agent_reported (not yet implemented — placeholder for future .status file)
  // 2. tool_call from session file (humanised)
  // 3. inferred from last assistant text
  // 4. stale / idle fallback
  let activityText = parsed.activityText;
  let activityType = parsed.activityType;

  // Check for .status file (agent-reported — future feature, already prepared)
  const statusFile = path.join(agentDir, '.status');
  if (fs.existsSync(statusFile)) {
    try {
      const statusData = JSON.parse(fs.readFileSync(statusFile, 'utf8'));
      const statusAge = now - new Date(statusData.timestamp || 0).getTime();
      if (statusAge < ACTIVE_WINDOW_MS && statusData.activity) {
        activityText = statusData.activity;
        activityType = 'agent_reported';
      }
    } catch (e) {}
  }

  if (!activityText || !wasRecentlyActive) {
    // Idle fallback
    const hoursAgo = Math.floor(activityAgeMs / 3600000);
    const minsAgo = Math.floor(activityAgeMs / 60000);
    if (activityAgeMs > IDLE_TEXT_THRESHOLD_MS) {
      activityText = hoursAgo > 0 ? `Idle — last active ${hoursAgo}h ago` : 'Idle — ready';
    } else if (activityAgeMs > STUCK_THRESHOLD_MS) {
      activityText = `Idle — last active ${minsAgo}m ago`;
    } else {
      activityText = activityText || 'Idle — ready';
    }
    activityType = wasRecentlyActive ? (activityType || 'stale') : 'stale';
  }

  // ── Session cost ───────────────────────────────────────────────────────────
  // Accumulate cost from session metadata if available
  let costUsd = parsed.cost;
  if (costUsd === null && bestSession.inputTokens) {
    // Rough estimate: claude-4-x pricing ~$3/M input, ~$15/M output
    const inputCost = (bestSession.inputTokens || 0) / 1_000_000 * 3.0;
    const outputCost = (bestSession.outputTokens || 0) / 1_000_000 * 15.0;
    const cacheReadCost = (bestSession.cacheRead || 0) / 1_000_000 * 0.30;
    const cacheWriteCost = (bestSession.cacheWrite || 0) / 1_000_000 * 3.75;
    costUsd = inputCost + outputCost + cacheReadCost + cacheWriteCost;
    if (costUsd < 0.001) costUsd = null; // don't show tiny amounts
  }

  // ── Session duration ──────────────────────────────────────────────────────
  let durationSeconds = 0;
  if (parsed.sessionStartedAt) {
    const startMs = new Date(parsed.sessionStartedAt).getTime();
    durationSeconds = Math.max(0, Math.floor((lastActivityMs - startMs) / 1000));
  }

  // ── Sub-agents ────────────────────────────────────────────────────────────
  // Look for recently active subagent sessions
  const subAgents = [];
  for (const [key, session] of Object.entries(sessions)) {
    if (!key.includes('subagent')) continue;
    const subAge = now - (session.updatedAt || 0);
    if (subAge < ACTIVE_WINDOW_MS) {
      // Try to get a meaningful label from the session file (first task description)
      let label = 'sub-agent';
      if (session.sessionFile && fs.existsSync(session.sessionFile)) {
        try {
          const startBuf = Buffer.alloc(1024);
          const sfd = fs.openSync(session.sessionFile, 'r');
          const bytesRead = fs.readSync(sfd, startBuf, 0, 1024, 0);
          fs.closeSync(sfd);
          const firstLines = startBuf.slice(0, bytesRead).toString('utf8').split('\n');
          for (const line of firstLines) {
            if (!line.trim()) continue;
            try {
              const e = JSON.parse(line);
              if (e.type === 'message' && e.message && e.message.role === 'user') {
                const content = e.message.content;
                let text = '';
                if (Array.isArray(content)) {
                  for (const c of content) {
                    if (c.type === 'text' && c.text) { text = c.text; break; }
                  }
                } else if (typeof content === 'string') {
                  text = content;
                }
                // Extract short label from task description
                const match = text.match(/You are (?:a |an )?([^.]+?)\./);
                if (match) {
                  label = match[1].slice(0, 30).trim();
                } else if (text.length > 0) {
                  // Take first meaningful words
                  label = text.replace(/\n/g, ' ').trim().slice(0, 30);
                }
                break;
              }
            } catch (e) {}
          }
        } catch (e) {}
      }
      subAgents.push({
        label,
        status: subAge < 5 * 60 * 1000 ? 'active' : 'idle',
        duration_seconds: Math.floor(subAge / 1000),
      });
    }
  }

  return {
    session_key: bestKey,
    agent_id: agentId,
    display_name: meta.name,
    emoji: meta.emoji,
    role: meta.role,
    status,
    activity: activityText,
    activity_type: activityType,
    activity_since_seconds: Math.floor((parsed.activitySinceMs || activityAgeMs) / 1000),
    last_activity_at: new Date(lastActivityMs).toISOString(),
    session_started_at: parsed.sessionStartedAt || new Date(bestUpdatedAt).toISOString(),
    discord_channel_id: meta.channel,
    sub_agents: subAgents,
    cost_usd: costUsd !== null ? parseFloat(costUsd.toFixed(4)) : null,
    // V1 compat fields (for installed app)
    id: agentId,
    name: meta.name,
    health: health,
    duration_seconds: durationSeconds,
    last_activity: new Date(lastActivityMs).toISOString(),
    channel: meta.channel,
    cost: costUsd !== null ? { session_total: parseFloat(costUsd.toFixed(4)) } : null,
    _recentActivity: parsed.recentEntries,
  };
}

// ─── Gateway uptime ───────────────────────────────────────────────────────────

function getGatewayUptime() {
  try {
    const pid = execSync('pgrep -f "openclaw.*gateway" 2>/dev/null | head -1').toString().trim();
    if (pid) {
      const startTime = execSync(`ps -p ${pid} -o lstart= 2>/dev/null`).toString().trim();
      if (startTime) {
        const start = new Date(startTime);
        const ageMs = Date.now() - start.getTime();
        const seconds = Math.floor(ageMs / 1000);
        return { uptime_seconds: seconds, uptime_human: formatUptime(seconds) };
      }
    }
  } catch (e) {}
  return { uptime_seconds: 0, uptime_human: '–' };
}

function formatUptime(seconds) {
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  const hours = Math.floor(seconds / 3600);
  const days = Math.floor(hours / 24);
  return days > 0 ? `${days}d ${hours % 24}h` : `${hours}h`;
}

// ─── Response builders ────────────────────────────────────────────────────────

function buildV2ActiveSessions() {
  const agentIds = Object.keys(AGENT_META);
  const agents = [];
  for (const id of agentIds) {
    const s = getAgentStatusV2(id);
    if (s) agents.push(s);
  }

  const { uptime_seconds } = getGatewayUptime();

  return {
    hostname: os.hostname().replace(/\.local$/, ''),
    uptime_seconds,
    agents,
  };
}

function buildV2Status() {
  const { uptime_seconds } = getGatewayUptime();
  // Attempt to read gateway version from package.json
  let gatewayVersion = 'unknown';
  try {
    const pkgPath = path.join(os.homedir(), '.openclaw', 'package.json');
    if (fs.existsSync(pkgPath)) {
      const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
      gatewayVersion = pkg.version || 'unknown';
    }
  } catch (e) {}

  return {
    hostname: os.hostname().replace(/\.local$/, ''),
    status: 'healthy',
    gateway_version: gatewayVersion,
    uptime_seconds,
  };
}

// Build legacy V1 shape (for the installed ClawView.app which reads this format)
function buildLegacyStatus() {
  const agentIds = Object.keys(AGENT_META);
  const agents = [];
  for (const id of agentIds) {
    const s = getAgentStatusV2(id);
    if (s) {
      // Return only V1-expected fields
      agents.push({
        id: s.agent_id,
        name: s.display_name,
        emoji: s.emoji,
        role: s.role,
        status: s.status,
        activity: s.activity,
        duration_seconds: s.duration_seconds,
        health: s.health,
        last_activity: s.last_activity_at,
        channel: s.discord_channel_id,
        sub_agents: s.sub_agents,
        cost: s.cost,
        _recentActivity: s._recentActivity,
      });
    }
  }

  const { uptime_human } = getGatewayUptime();

  return {
    hostname: os.hostname().replace(/\.local$/, ''),
    uptime: uptime_human,
    connection: 'local',
    agents,
    timestamp: new Date().toISOString(),
  };
}

// ─── HTTP Server ──────────────────────────────────────────────────────────────

// Check if already running before binding
const testReq = http.request(
  { host: '127.0.0.1', port: PORT, path: '/health', method: 'GET' },
  (res2) => {
    let body = '';
    res2.on('data', d => body += d);
    res2.on('end', () => {
      try {
        const j = JSON.parse(body);
        if (j.ok) {
          console.log(`[clawview-status-server] Already running on port ${PORT}. Exiting.`);
          process.exit(0);
        }
      } catch (e) {}
      startServer();
    });
  }
);
testReq.on('error', () => startServer());
testReq.setTimeout(500, () => { testReq.destroy(); startServer(); });
testReq.end();

function startServer() {
  const server = http.createServer((req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');

    // ── V2 endpoints ───────────────────────────────────────────────────────
    if (req.url === '/api/sessions/active' && req.method === 'GET') {
      try {
        const data = buildV2ActiveSessions();
        res.writeHead(200);
        res.end(JSON.stringify(data));
      } catch (e) {
        res.writeHead(500);
        res.end(JSON.stringify({ error: e.message }));
      }

    } else if (req.url === '/api/status' && req.method === 'GET') {
      try {
        const data = buildV2Status();
        res.writeHead(200);
        res.end(JSON.stringify(data));
      } catch (e) {
        res.writeHead(500);
        res.end(JSON.stringify({ error: e.message }));
      }

    // ── Nudge endpoint (stub — agent routing is gateway's job) ────────────
    } else if (req.url.startsWith('/api/sessions/') && req.url.endsWith('/nudge') && req.method === 'POST') {
      // For v1.0: acknowledge the nudge but note it's not fully wired
      // The Gateway would need to route this; for now we log it
      let body = '';
      req.on('data', d => body += d);
      req.on('end', () => {
        console.log(`[nudge] ${req.url}: ${body}`);
        res.writeHead(202);
        res.end(JSON.stringify({ status: 'received', note: 'Gateway routing not yet implemented' }));
      });
      return;

    // ── Legacy V1 endpoints (backward compat for installed app) ──────────
    } else if (req.url === '/api/clawview/status' || req.url === '/status') {
      try {
        const data = buildLegacyStatus();
        res.writeHead(200);
        res.end(JSON.stringify(data));
      } catch (e) {
        res.writeHead(500);
        res.end(JSON.stringify({ error: e.message }));
      }

    } else if (req.url === '/health') {
      res.writeHead(200);
      res.end(JSON.stringify({ ok: true, version: 2 }));

    } else {
      res.writeHead(404);
      res.end(JSON.stringify({ error: 'Not found' }));
    }
  });

  server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
      console.log(`[clawview-status-server] Port ${PORT} already in use. Exiting.`);
      process.exit(0);
    } else {
      throw err;
    }
  });

  server.listen(PORT, '127.0.0.1', () => {
    console.log(`[clawview-status-server] V2 running at http://127.0.0.1:${PORT}`);
    console.log(`  GET /api/status            — Gateway health`);
    console.log(`  GET /api/sessions/active   — V2 agent list`);
    console.log(`  GET /api/clawview/status   — Legacy V1 shape`);
  });
}

// ─── Graceful shutdown ────────────────────────────────────────────────────────

process.on('SIGTERM', () => process.exit(0));
process.on('SIGINT', () => process.exit(0));

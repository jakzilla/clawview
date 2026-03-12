# Agent Status Reporting

Report your current activity to ClawView so Jack can see what you're doing in real time.

## When to report

**At task start** — immediately after reading your brief/issue, before doing any work:
```bash
node -e "
const fs=require('fs'),os=require('os'),path=require('path');
const id=process.env.OPENCLAW_AGENT_ID||'main';
const dir=path.join(os.homedir(),'.openclaw','agents',id);
fs.mkdirSync(dir,{recursive:true});
fs.writeFileSync(path.join(dir,'.status'),JSON.stringify({
  timestamp: new Date().toISOString(),
  state: 'active',
  activity: 'REPLACE_WITH_TASK_DESCRIPTION'
}));
" 2>/dev/null || true
```

**At task end** — after your final action (merge, deploy, message sent):
```bash
node -e "
const fs=require('fs'),os=require('os'),path=require('path');
const id=process.env.OPENCLAW_AGENT_ID||'main';
const dir=path.join(os.homedir(),'.openclaw','agents',id);
fs.writeFileSync(path.join(dir,'.status'),JSON.stringify({
  timestamp: new Date().toISOString(),
  state: 'done',
  activity: 'REPLACE_WITH_COMPLETION_SUMMARY'
}));
" 2>/dev/null || true
```

## Activity text guidelines

Be specific and human-readable. Jack will read this directly.

**Good:**
- `Fixing issue #75 — subagent session lookup`
- `Building PR #78 — active/idle status gate`
- `Running Codex review on PR #76`
- `Done — merged PR #78, ClawView deployed`

**Bad:**
- `Working` (too vague)
- `Running command` (that's a tool call name, not an activity)
- `Executing task` (meaningless)

## Agent IDs

| Agent | OPENCLAW_AGENT_ID |
|-------|------------------|
| Clawdia | `main` |
| Linus | `dev` |
| Steve | `jony` |
| Richard | `marketing` |
| Prawn | `pa` |
| Santa | `intake` |

If you don't know your agent ID, use `main` — it's better than nothing.

## Status file location

`~/.openclaw/agents/{id}/.status`

Format:
```json
{
  "timestamp": "2026-03-12T14:00:00.000Z",
  "state": "active",
  "activity": "Fixing issue #75 — subagent session lookup"
}
```

States: `active` (working), `done` (finished), `idle` (nothing happening)

The ClawView status server polls this file and shows it in the menu bar app. Active entries are trusted for up to 30 minutes. Done/idle entries immediately clear the active state.

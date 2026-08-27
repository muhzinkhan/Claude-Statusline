# Claude Code Status Line (Windows)

A custom status line for [Claude Code](https://claude.com/claude-code) on Windows/PowerShell. Shows your model, context usage, tokens, project, git branch, and rate limits — all in one line.

![Status line preview](/preview/preview.png)

## What it shows

- **Model** — e.g. `Opus 5`
- **Context ring** — a circle that fills up (`○ ◔ ◑ ◕ ●`) + % of context window used
- **Tokens** — used / total (e.g. `200k/1M`)
- **Project folder**
- **Git branch** (only shown inside a repo)
- **Rate limit** — 5h or 7d usage as a 10-block bar + %, plus a countdown to when it resets

Colors turn green → yellow → red as usage climbs, so you can tell at a glance when you're getting close to a limit.

The ring fills in five steps: `○` up to 9%, `◔` to 37.5%, `◑` to 62.5%, `◕` to 87.5%, then `●`.

Green below 30%, yellow 30–59%, red 60% and up — the same rule colours both the ring and the
rate limit bar, so every "how full am I" number on the line speaks one language.

## Setup

1. Copy `statusline.ps1` to `~/.claude/statusline.ps1`.
2. Add this to `~/.claude/settings.json` (merge it in, don't replace the file):

   ```json
   "statusLine": {
     "type": "command",
     "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ~/.claude/statusline.ps1"
   }
   ```

3. Restart Claude Code. The new status line will show up at the bottom.

## Testing

Want to check it works before trusting it? Run the included tests:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-payloads.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-git-branch.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-ring-bands.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-color-thresholds.ps1
```

The first two print lines for you to eyeball against an expected list. The last two assert
the ring bands and the colour thresholds, and exit non-zero if either drifts.

## Want the full details?

See [statusline.md](statusline.md) for the complete build spec, every edge case handled, and how to customize colors, thresholds, and segments.

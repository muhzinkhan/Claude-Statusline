# Recreate: Claude Code status line (Windows / PowerShell)

Instructions for an agent to rebuild this status line from scratch on a Windows machine.
Follow the steps in order. The **Gotchas** section is not optional — every item in it is a
bug that was actually hit and fixed during the original build.

## Files in this folder

| Path | Purpose |
|---|---|
| `statusline.md` | This document — the full recreation spec. |
| `statusline.ps1` | Reference copy of the script. The **live** copy Claude Code actually runs lives at `~/.claude/statusline.ps1`; this is the source of truth to copy from. |
| `tests/test-payloads.ps1` | Renders the line against 13 payload shapes (thresholds, reset clock, missing keys, malformed input). |
| `tests/test-git-branch.ps1` | Exercises the branch segment across 5 repo states, using throwaway repos under `$env:TEMP`. |

Both test scripts default to testing the installed copy at `~/.claude/statusline.ps1`.
Pass `-Script .\statusline.ps1` to test the local reference copy instead.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-payloads.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-git-branch.ps1
```

If you edit `statusline.ps1` here, copy it to `~/.claude/statusline.ps1` to take effect.

## Goal

A single-line status bar with seven segments, separated by a dim `|`:

```
Opus 5 | ○ 8% | 76k/1M | my-project | feature/status-bar | 5h ██░░░░░░░░ 23% ↻ 2h14m
```

| # | Segment | Source field | Color |
|---|---------|--------------|-------|
| 1 | Model name | `model.display_name` | Claude orange `#D97757` (24-bit) |
| 2 | Context ring (Harvey ball, see bands below) | `context_window.used_percentage` | threshold: green / yellow / red |
| 3 | Context **used** % | `context_window.used_percentage` | same threshold color |
| 4 | Tokens used / window size | derived (see Gotcha 4) | dim |
| 5 | Current directory (leaf only) | `workspace.current_dir` | dim |
| 6 | Git branch, only inside a repo | `git branch --show-current` | blue |
| 7 | Rate limit 10-block bar + %, 5h → 7d fallback | `rate_limits.*.used_percentage` | same threshold color |
| 7 | ↻ time until that window resets | `rate_limits.*.resets_at` | dim |

The ring glyph is picked from explicit bands, not by rounding — the empty and full
glyphs get deliberately narrow ones, so `●` means "genuinely nearly full" rather than
"rounded up from 88".

| Band | Glyph |
|---|---|
| 0 – 9 | `○` |
| >9 – <37.5 | `◔` |
| 37.5 – 62.5 | `◑` |
| >62.5 – <87.5 | `◕` |
| 87.5+ | `●` |

Each band opens inclusive and closes exclusive, which is what puts 37.5 on `◑` and 87.5
on `●`. Note `○` covers everything up to 9%, so a barely-used context reads as empty.

Threshold colors are keyed on **percent used**: green below 50, yellow 50–79, red 80+.
The *same* rule drives segments 2, 3 and 7, so every "how full am I" number on the line
speaks one language. Segment 7 leads with its window label (`5h` / `7d`) because the bare
percentage is ambiguous once a clock sits next to it.

The reset clock renders `↻ 2h14m`, `↻ 47m`, `↻ 4d5h`, or `↻ now` when the reset has passed.
It is dim so the eye lands on the percentage.

Colour variants considered and rejected: cyan usage with a dim clock (no shared rule with
the context bar); a magenta clock (a sixth colour on one line); and a segment that stays
dim until 80% (loses at-a-glance reading during normal use).

Every segment is individually optional. If its data is absent the segment — and its
separator — disappears, leaving the rest of the line intact.

## Step 1 — Write the script

Create `~/.claude/statusline.ps1`. Save as **UTF-8 without BOM** and use **LF** line endings.

```powershell
$raw = [Console]::In.ReadToEnd()
try { $data = $raw | ConvertFrom-Json } catch { return }
if (-not $data) { return }

# Block-drawing characters in the progress bar need a UTF-8 console.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}

$esc    = [char]27
$orange = "$esc[38;2;217;119;87m"   # Claude orange (#D97757)
$cyan   = "$esc[36m"
$blue   = "$esc[38;2;97;175;239m"   # branch (#61AFEF)
$green  = "$esc[32m"
$yellow = "$esc[33m"
$red    = "$esc[31m"
$dim    = "$esc[2m"
$reset  = "$esc[0m"

function Format-Tokens($n) {
    if ($n -ge 1000000) { return (("{0:N1}" -f ($n / 1000000)) -replace '\.0$', '') + "M" }
    return "{0:N0}k" -f ($n / 1000)
}

# Shared by the context bar and the rate limit, so both "how full am I" numbers read alike.
function Get-ThresholdColor($pct) {
    if ($pct -lt 50) { return $green } elseif ($pct -lt 80) { return $yellow } else { return $red }
}

# Round to the nearest minute before decomposing: TimeSpan.Minutes truncates, so a real
# 2h13m59s would otherwise read "2h13m" for almost the whole minute. Floor the division —
# [int] rounds, which would turn 170 minutes into "3h50m".
function Format-TimeLeft($span) {
    if ($span.TotalMinutes -lt 1) { return "now" }
    $mins = [int][math]::Round($span.TotalMinutes)
    if ($mins -lt 60)   { return "${mins}m" }
    if ($mins -lt 1440) { return "$([int][math]::Floor($mins / 60))h$($mins % 60)m" }
    $hours = [int][math]::Round($span.TotalHours)
    return "$([int][math]::Floor($hours / 24))d$($hours % 24)h"
}

$parts = @()

# 1. Model name
$model = $data.model.display_name
if ($model) { $parts += "$orange$model$reset" }

# 2 + 3. Context bar and used percentage, threshold-colored
$ctx     = $data.context_window
$usedPct = $ctx.used_percentage
if ($null -ne $usedPct) {
    # Clamp with explicit doubles: [math]::Min(100, 12.6) binds the int overload and rounds.
    $pct = [double]$usedPct
    if ($pct -lt 0) { $pct = 0 } elseif ($pct -gt 100) { $pct = 100 }
    $color  = Get-ThresholdColor $pct
    # Harvey ball on explicit bands, not arithmetic rounding. The empty and full glyphs get
    # narrow bands so the ring only reads full from 87.5% up. Each band opens inclusive,
    # which is what puts 37.5 on the half and 87.5 on the full.
    if     ($pct -le 9)    { $glyph = 0x25CB }   # circle
    elseif ($pct -lt 37.5) { $glyph = 0x25D4 }   # quarter
    elseif ($pct -le 62.5) { $glyph = 0x25D1 }   # half
    elseif ($pct -lt 87.5) { $glyph = 0x25D5 }   # three quarters
    else                   { $glyph = 0x25CF }   # full
    $bar = [string][char]$glyph
    $parts += "$color$bar $([math]::Round($pct))%$reset"

    # 4. Tokens used out of the context window size
    $size = $ctx.context_window_size
    if ($size) {
        $used = [int][math]::Round($size * $pct / 100)
        $parts += "$dim$(Format-Tokens $used)/$(Format-Tokens $size)$reset"
    }
}

# 5. Current directory
$dir = $data.workspace.current_dir
if ($dir) {
    $dirName = Split-Path $dir -Leaf
    if ($dirName) { $parts += "$dim$dirName$reset" }
}

# 6. Git branch, when the current directory is inside a repo
if ($dir -and (Test-Path $dir)) {
    Push-Location $dir
    $branch = git --no-optional-locks branch --show-current 2>$null
    Pop-Location
    if ($branch) { $parts += "$blue$($branch.Trim())$reset" }
}

# 7. Rate limit usage, plus time until that window resets
$rl    = $data.rate_limits
$label = $null
if     ($null -ne $rl.five_hour.used_percentage) { $label = "5h"; $win = $rl.five_hour }
elseif ($null -ne $rl.seven_day.used_percentage) { $label = "7d"; $win = $rl.seven_day }

if ($label) {
    # Clamp before deriving the bar: an out-of-range percentage would make the pad
    # count negative. Same explicit-double clamp as the context window (Gotcha 1).
    $rlPct = [double]$win.used_percentage
    if ($rlPct -lt 0) { $rlPct = 0 } elseif ($rlPct -gt 100) { $rlPct = 100 }
    $rlFill = [int][math]::Round($rlPct / 10)
    $rlBar  = ([string][char]0x2588) * $rlFill + ([string][char]0x2591) * (10 - $rlFill)
    $seg    = "$(Get-ThresholdColor $rlPct)$label $rlBar $([math]::Round($rlPct))%$reset"

    # resets_at is unix epoch seconds (the CLI reads it as new Date(resets_at * 1000)).
    if ($win.resets_at) {
        $left = [DateTimeOffset]::FromUnixTimeSeconds([int64]$win.resets_at) - [DateTimeOffset]::Now
        $seg += " $dim$([string][char]0x21BB) $(Format-TimeLeft $left)$reset"
    }
    $parts += $seg
}

[Console]::Out.Write(($parts -join " $dim|$reset "))
```

## Step 2 — Register it

Add this key to `~/.claude/settings.json` (user-level, so it applies to every project).
**Merge** it into the existing JSON — do not overwrite the file and lose the user's other settings.

```json
"statusLine": {
  "type": "command",
  "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ~/.claude/statusline.ps1"
}
```

The status line takes effect on the next Claude Code start.

## Gotchas

These are the traps. Each one produced a visible defect before it was fixed.

**1. `[math]::Min` / `[math]::Max` silently round doubles.**
`[math]::Min(100, 12.6)` binds the `Min(int, int)` overload and returns `13`, not `12.6`.
Clamping the percentage this way corrupts every value derived from it — the token count
rendered `26k` instead of `25k`, and `910k` instead of `913k`. Cast to `[double]` and
clamp with plain `-lt` / `-gt` comparisons instead.

**2. Circle and block glyphs need an explicit UTF-8 console.**
Windows PowerShell 5.1 mangles `○ ◔ ◑ ◕ ●` (U+25CB, U+25D4, U+25D1, U+25D5, U+25CF) and the
rate limit's `█ ░` (U+2588, U+2591) under the default OEM codepage. Set `[Console]::OutputEncoding` at the top of the script, wrapped in `try/catch`
so a restricted host can't kill the whole line. Build the characters with
`[char]0x25CB` / `[char]0x2588` rather than pasting literals, so the script survives
being saved in a non-UTF-8 encoding.

**3. Use `[Console]::Out.Write`, not `Write-Output`.**
`Write-Output` appends CRLF, leaving a stray carriage return in a single-line status bar.

**4. Derive the token count from the percentage, not from `total_input_tokens`.**
`used = context_window_size × used_percentage / 100` guarantees segment 4 can never
disagree with the percentage sitting right beside it. The raw `total_input_tokens` field
is computed differently and can drift by a few thousand tokens, which looks like a bug.

**5. `git branch --show-current`, not `rev-parse --abbrev-ref HEAD`.**
`rev-parse` fails on an unborn branch — a freshly `git init`ed repo with no commits shows
nothing at all. `--show-current` handles it. Empty output already covers both "not a repo"
and "detached HEAD", so no `$LASTEXITCODE` check is needed. Always pass
`--no-optional-locks` so the status line never contends with a running git command.

**6. The `~` in the settings command is fine.**
Claude Code runs hook commands through Git Bash on Windows, and `powershell.exe -File`
resolves `~`. Use forward slashes; backslashes will not survive.

**7. Guard the JSON parse.**
Malformed stdin must `return` silently. Without `try/catch`, a PowerShell stack trace is
printed into the status bar on every refresh.

**8. `TimeSpan.Minutes` truncates, and `[int]` on a division rounds.**
Both bite the reset clock. A real 2h13m59s remaining renders as `2h13m` for almost the
whole minute, because `.Minutes` drops the seconds — so round `TotalMinutes` to the nearest
minute *first*, then decompose. But decompose with `[math]::Floor`, not `[int]`: `[int]`
rounds to nearest, which turns 170 minutes into `3h50m` instead of `2h50m`. The two fixes
pull in opposite directions and you need both.

**9. `resets_at` is unix epoch *seconds*, not milliseconds.**
Confirmed by how the CLI itself consumes it: `new Date(resets_at * 1000)`. Use
`[DateTimeOffset]::FromUnixTimeSeconds()`. Feeding it to `FromUnixTimeMilliseconds()` puts
the reset in 1970 and the clock reads `now` forever.

**10. Clamp the clock at zero.**
A reset timestamp can sit in the past between windows. Without a `TotalMinutes -lt 1` guard
the segment renders a negative duration.

**11. Don't add a git-dirty indicator casually.**
It needs a second subprocess (`git status --porcelain`), on top of an existing
`powershell.exe` cold start (~150–250 ms) and one `git` call, on every refresh. On a large
repo the lag is visible. Everything else in this line is already in the stdin JSON and
costs nothing.

## Status line payload reference

The JSON delivered on stdin. Verified against the Claude Code CLI binary — fields marked
*conditional* are absent entirely when they don't apply, so always null-check.

| Field | Notes |
|---|---|
| `model.id`, `model.display_name` | |
| `workspace.current_dir`, `.project_dir`, `.added_dirs[]` | `project_dir` enables a path relative to project root |
| `workspace.git_worktree`, `worktree.{name,path,branch}` | *conditional* |
| `context_window.used_percentage` / `.remaining_percentage` | always ship **together**, from the same function — no fallback needed between them |
| `context_window.context_window_size` | `200000`, or `1000000` on a 1M-context model |
| `context_window.total_input_tokens`, `.total_output_tokens`, `.current_usage` | `current_usage` is an object, not a number |
| `exceeds_200k_tokens` | boolean |
| `cost.{total_cost_usd, total_duration_ms, total_api_duration_ms, total_lines_added, total_lines_removed}` | |
| `rate_limits.five_hour.{used_percentage, resets_at}` | *conditional*; `resets_at` is **unix epoch seconds** and is itself optional within the window |
| `rate_limits.seven_day.{used_percentage, resets_at}` | *conditional*, and **independent** of `five_hour` — either can appear alone |
| `fast_mode`, `effort.level`, `thinking.enabled` | |
| `agent.name` | *conditional* — set while a subagent runs |
| `pr.{number, url, review_state, kind}` | *conditional* |
| `vim.mode`, `session_name`, `remote.session_id`, `version`, `output_style.name` | |
| `session_id`, `transcript_path`, `cwd`, `hook_event_name` | standard hook fields |

## Step 3 — Verify

Do not declare this done without running it. Pipe test payloads to the script directly:

```powershell
$sl = "$HOME\.claude\statusline.ps1"
@"
{"model":{"display_name":"Opus 5"},
 "workspace":{"current_dir":"C:/Users/me/my-project"},
 "context_window":{"used_percentage":12.6,"context_window_size":200000},
 "rate_limits":{"five_hour":{"used_percentage":23.1}}}
"@ | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sl
```

Note: when building test JSON, use **forward slashes** in Windows paths. A literal `\` is an
invalid JSON escape, the parse fails, and the script correctly prints nothing — which is
easy to misread as a bug in the script.

Cover these cases and confirm each expected result:

| Case | Expected |
|---|---|
| `used_percentage: 12.6`, size 200000 | `◔ 13%` green, `25k/200k` — **not** `26k` |
| `used_percentage: 64` | `◕ 64%` yellow, `128k/200k` |
| `used_percentage: 91.3`, size 1000000 | `● 91%` red, `913k/1M` |
| `five_hour` 23%, resets in 2h14m | `5h ██░░░░░░░░ 23%` green, clock `↻ 2h14m` — **not** `2h13m` (Gotcha 8) |
| `five_hour` 64%, resets in 47m | `5h ██████░░░░ 64%` yellow, clock `↻ 47m` |
| `five_hour` 84% | `5h ████████░░ 84%` red — same threshold rule as the context ring |
| `resets_at` in the past | `↻ now`, never a negative duration |
| `seven_day` only, 4d5h out | `7d ████░░░░░░ 44%`, clock `↻ 4d5h` — **not** `↻ 101h` |
| usage present, `resets_at` absent | `5h ██░░░░░░░░ 23%` alone, no clock |
| reset 170 minutes out | `↻ 2h50m` — **not** `↻ 3h50m` (Gotcha 8) |
| reset 1440 minutes out | `↻ 1d0h` |
| no `rate_limits` key | line ends after directory/branch, no trailing `\|` |
| no `context_window` key | segments 2–4 all absent, rest of line intact |
| `used_percentage: 9` / `9.1` | `○ 9%` / `◔ 9%` — the first band edge |
| `used_percentage: 37.5` / `62.5` | both `◑ 38%` / `◑ 63%` — the half band is closed at both ends |
| `used_percentage: 87.4` / `87.5` | `◕ 87%` / `● 88%` — full starts exactly at 87.5 |
| `{}` | prints nothing, exit 0 |
| non-JSON input | prints nothing, exit 0 |
| repo with commits | branch in blue |
| `git init`, no commits (unborn) | branch name still shown |
| detached HEAD | branch segment omitted |
| not a repo / nonexistent dir | branch segment omitted |

## Customizing

- **Reorder** segments by moving the `$parts +=` blocks; order in the array is order on screen.
- **Ring bands**: the `-le 9` / `-lt 37.5` / `-le 62.5` / `-lt 87.5` chain. Widen or narrow
  any band by moving one comparison; keep them ordered, since the chain returns on first match.
- **Ring resolution**: quarter-resolution is the ceiling. Unicode has no finer monochrome pie
  set, so more steps means changing shape: `@(0x2581..0x2588)` gives an 8-level vertical meter
  in one cell, and the original 10-block bar was
  `([string][char]0x2588) * [int][math]::Round($pct / 10)` padded out with `0x2591`.
- **Bigger ring**: not really possible. Terminal cells are fixed-size, and only the endpoints
  have large variants (`0x25EF`, `0x2B24`), so the set would change size as it fills. Moon
  phase emoji (`0x1F311`..`0x1F315`) are double-width and 8-step, but force their own colour
  and would break the shared threshold palette.
- **Rate limit bar width**: change `10` in both `$rlFill` (`$rlPct / 10`) and the
  `(10 - $rlFill)` padding. The context ring and this bar are deliberately different
  resolutions — 4 steps vs 10 — so swap `$ring` in for `$rlBar` if you want them to match.
- **Thresholds**: the `-lt 50` / `-lt 80` comparisons in `Get-ThresholdColor`, which drives
  segments 2, 3 and 7 together. Split it into two functions to colour the context ring and
  the rate limit on different scales.
- **Reset clock glyph**: `[char]0x21BB` (`↻`). Use `~` to stay ASCII.
- **Clock colour**: it is `$dim`; make it `$cyan` or `$magenta` to give time its own colour.
- **Drop the clock** entirely by removing the `if ($win.resets_at)` block — the percentage
  keeps working on its own.
- **Show remaining instead of used**: swap to `$ctx.remaining_percentage` and invert the
  threshold comparisons.
- **Detached HEAD**: to show a short SHA instead of nothing, fall back to
  `git --no-optional-locks rev-parse --short HEAD` when `--show-current` returns empty.
- **Truecolor**: the orange is 24-bit ANSI. On a terminal without truecolor support,
  substitute 256-color `` `e[38;5;173m ``.

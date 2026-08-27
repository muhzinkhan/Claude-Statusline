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

# Shared by the context ring and the rate limit bar, so both "how full am I" numbers read alike.
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

# 2 + 3. Context ring and used percentage, threshold-colored
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

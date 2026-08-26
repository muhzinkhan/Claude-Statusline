$raw = [Console]::In.ReadToEnd()
try { $data = $raw | ConvertFrom-Json } catch { return }
if (-not $data) { return }

# Block-drawing characters in the progress bar need a UTF-8 console.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}

$esc    = [char]27
$orange = "$esc[38;2;217;119;87m"   # Claude orange (#D97757)
$cyan   = "$esc[36m"
$green  = "$esc[32m"
$yellow = "$esc[33m"
$red    = "$esc[31m"
$dim    = "$esc[2m"
$reset  = "$esc[0m"

function Format-Tokens($n) {
    if ($n -ge 1000000) { return (("{0:N1}" -f ($n / 1000000)) -replace '\.0$', '') + "M" }
    return "{0:N0}k" -f ($n / 1000)
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
    $color  = if ($pct -lt 50) { $green } elseif ($pct -lt 80) { $yellow } else { $red }
    $filled = [int][math]::Round($pct / 10)
    $bar    = ([string][char]0x2588) * $filled + ([string][char]0x2591) * (10 - $filled)
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
    if ($branch) { $parts += "$green$($branch.Trim())$reset" }
}

# 7. Rate limit usage (5-hour window, falling back to 7-day)
$rl = $data.rate_limits
if ($null -ne $rl.five_hour.used_percentage) {
    $parts += "$cyan$([math]::Round($rl.five_hour.used_percentage))% 5h$reset"
} elseif ($null -ne $rl.seven_day.used_percentage) {
    $parts += "$cyan$([math]::Round($rl.seven_day.used_percentage))% 7d$reset"
}

[Console]::Out.Write(($parts -join " $dim|$reset "))

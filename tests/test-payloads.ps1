# Feeds representative status line payloads to the script and prints the rendered line.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-payloads.ps1
#        ...-File tests\test-payloads.ps1 -Script .\statusline.ps1   (test the local copy)

param([string]$Script = "$HOME\.claude\statusline.ps1")

if (-not (Test-Path $Script)) { throw "Status line script not found: $Script" }

# Forward slashes on purpose: a literal \ is an invalid JSON escape and the parse would fail.
$dir = "C:/Users/me/my-project"

function Run($label, $json) {
    $out = $json | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script
    Write-Host ("{0,-32} {1}" -f $label, $out)
}

Write-Host "Testing: $Script`n"

Run "low usage (green) + 5h limit" @"
{"model":{"display_name":"Opus 5"},
 "workspace":{"current_dir":"$dir"},
 "context_window":{"used_percentage":12.6,"context_window_size":200000},
 "rate_limits":{"five_hour":{"used_percentage":23.1}}}
"@

Run "mid usage (yellow)" @"
{"model":{"display_name":"Opus 5"},
 "workspace":{"current_dir":"$dir"},
 "context_window":{"used_percentage":64.0,"context_window_size":200000},
 "rate_limits":{"five_hour":{"used_percentage":71.5}}}
"@

Run "high usage (red) + 1M window" @"
{"model":{"display_name":"Sonnet 5"},
 "workspace":{"current_dir":"$dir"},
 "context_window":{"used_percentage":91.3,"context_window_size":1000000},
 "rate_limits":{"seven_day":{"used_percentage":44.0}}}
"@

Run "no rate limits" @"
{"model":{"display_name":"Haiku 4.5"},
 "workspace":{"current_dir":"$dir"},
 "context_window":{"used_percentage":50,"context_window_size":200000}}
"@

Run "no context_window at all" @"
{"model":{"display_name":"Opus 5"},
 "workspace":{"current_dir":"$dir"},
 "rate_limits":{"five_hour":{"used_percentage":23.1}}}
"@

# --- rate limit window + reset clock ---
# resets_at is unix epoch seconds, so build these relative to now.
function Epoch($timespan) { [DateTimeOffset]::Now.Add($timespan).ToUnixTimeSeconds() }

Run "reset in 2h14m" @"
{"model":{"display_name":"Opus 5"},
 "workspace":{"current_dir":"$dir"},
 "context_window":{"used_percentage":8,"context_window_size":1000000},
 "rate_limits":{"five_hour":{"used_percentage":23.1,"resets_at":$(Epoch (New-TimeSpan -Hours 2 -Minutes 14))}}}
"@

Run "reset in 47m" @"
{"model":{"display_name":"Opus 5"},
 "workspace":{"current_dir":"$dir"},
 "context_window":{"used_percentage":8,"context_window_size":1000000},
 "rate_limits":{"five_hour":{"used_percentage":64,"resets_at":$(Epoch (New-TimeSpan -Minutes 47))}}}
"@

Run "rate limit 84% (red)" @"
{"model":{"display_name":"Opus 5"},
 "workspace":{"current_dir":"$dir"},
 "context_window":{"used_percentage":8,"context_window_size":1000000},
 "rate_limits":{"five_hour":{"used_percentage":84,"resets_at":$(Epoch (New-TimeSpan -Minutes 38))}}}
"@

Run "reset already past" @"
{"model":{"display_name":"Opus 5"},
 "workspace":{"current_dir":"$dir"},
 "context_window":{"used_percentage":8,"context_window_size":1000000},
 "rate_limits":{"five_hour":{"used_percentage":12,"resets_at":$(Epoch (New-TimeSpan -Minutes -5))}}}
"@

Run "7d window, 4d5h out" @"
{"model":{"display_name":"Opus 5"},
 "workspace":{"current_dir":"$dir"},
 "context_window":{"used_percentage":8,"context_window_size":1000000},
 "rate_limits":{"seven_day":{"used_percentage":44,"resets_at":$(Epoch (New-TimeSpan -Days 4 -Hours 5))}}}
"@

Run "usage but no resets_at" @"
{"model":{"display_name":"Opus 5"},
 "workspace":{"current_dir":"$dir"},
 "context_window":{"used_percentage":8,"context_window_size":1000000},
 "rate_limits":{"five_hour":{"used_percentage":23.1}}}
"@

Run "empty payload"   "{}"
Run "garbage payload" "not json at all"

Write-Host @"

Expected:
  low usage      ->  ring 13% green, 25k/200k   (NOT 26k - see Gotcha 1)
  mid usage      ->  ring 64% yellow, 128k/200k
  high usage     ->  ring 91% red, 913k/1M
  no rate limits ->  line ends after the directory, no trailing separator
  no context     ->  segments 2-4 absent, rest of the line intact

  Ring glyph per band (pinned properly by tests\test-ring-bands.ps1):
    0-9 empty, to 37.5 quarter, to 62.5 half, to 87.5 three-quarter, 87.5+ full.
    So the 8% rows below render an EMPTY ring, not a sliver.

  reset 2h14m    ->  5h bar 23% green,  clock reads 2h14m
  reset 47m      ->  5h bar 64% yellow, clock reads 47m
  84% red        ->  5h bar 84% red,    clock reads 38m
  reset past     ->  clock reads 'now', never a negative duration
  7d window      ->  7d bar 44%,        clock reads 4d5h (not 101h)
  no resets_at   ->  '5h bar 23%' alone, no clock

  The rate limit bar is 10 blocks; the context ring is 5 steps. Deliberately different.

  empty/garbage  ->  nothing at all
"@

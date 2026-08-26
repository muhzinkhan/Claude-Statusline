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

Run "empty payload"   "{}"
Run "garbage payload" "not json at all"

Write-Host @"

Expected:
  low usage      ->  13% green, 25k/200k   (NOT 26k - see Gotcha 1)
  mid usage      ->  64% yellow, 128k/200k
  high usage     ->  91% red, 913k/1M
  no rate limits ->  line ends after the directory, no trailing separator
  no context     ->  segments 2-4 absent, rest of the line intact
  empty/garbage  ->  nothing at all
"@

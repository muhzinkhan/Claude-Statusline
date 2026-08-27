# Pins Get-ThresholdColor at every boundary, for BOTH segments it drives.
# Each case feeds the same percentage to the context window and the rate limit, then asserts
# they came out the same colour — that shared rule is the whole point of the palette, and a
# refactor that split them would otherwise go unnoticed.
# Asserts and sets an exit code, like tests\test-ring-bands.ps1.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-color-thresholds.ps1
#        ...-File tests\test-color-thresholds.ps1 -Script .\statusline.ps1

param([string]$Script = "$HOME\.claude\statusline.ps1")

if (-not (Test-Path $Script)) { throw "Status line script not found: $Script" }

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}

$esc   = [char]27
$names = @{ '32' = 'green'; '33' = 'yellow'; '31' = 'red' }

# Any of the five ring glyphs may precede the context percentage.
$glyphs = -join @([char]0x25CB, [char]0x25D4, [char]0x25D1, [char]0x25D5, [char]0x25CF)

# pct, expected colour code, what the row pins down
$cases = @(
    @(0,    '32', "zero is green"),
    @(15,   '32', ""),
    @(29.9, '32', "top of green"),
    @(30,   '33', "yellow opens inclusive"),
    @(45,   '33', ""),
    @(59.9, '33', "top of yellow"),
    @(60,   '31', "red opens inclusive"),
    @(84,   '31', ""),
    @(100,  '31', "ceiling")
)

$inv    = [System.Globalization.CultureInfo]::InvariantCulture
$failed = 0

Write-Host "Testing: $Script`n"
Write-Host ("{0,6}  {1,-8} {2,-8} {3,-8} {4,-6} {5}" -f "pct", "ring", "ratebar", "expect", "result", "pins")

foreach ($case in $cases) {
    $pct = $case[0]; $want = $case[1]; $note = $case[2]
    $p   = $pct.ToString($inv)   # invariant: a comma decimal would be invalid JSON

    $json = '{"model":{"display_name":"X"},' +
            '"context_window":{"used_percentage":' + $p + ',"context_window_size":200000},' +
            '"rate_limits":{"five_hour":{"used_percentage":' + $p + '}}}'

    $raw = $json | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script

    # The colour code sits immediately before the ring glyph / the "5h" label.
    $ring = if ($raw -match "$esc\[(\d+)m[$glyphs]")  { $Matches[1] } else { '?' }
    $bar  = if ($raw -match "$esc\[(\d+)m5h ")        { $Matches[1] } else { '?' }

    $ok = ($ring -eq $want -and $bar -eq $want)
    if (-not $ok) { $failed++ }

    $fmt = { param($c) if ($names.ContainsKey($c)) { $names[$c] } else { $c } }
    Write-Host ("{0,6}  {1,-8} {2,-8} {3,-8} {4,-6} {5}" -f
        $pct, (& $fmt $ring), (& $fmt $bar), (& $fmt $want),
        $(if ($ok) { "pass" } else { "FAIL" }), $note)
}

Write-Host ""
if ($failed -eq 0) {
    Write-Host "All $($cases.Count) colour boundaries pass, ring and rate bar agreeing throughout."
    exit 0
} else {
    Write-Host "$failed of $($cases.Count) FAILED."
    exit 1
}

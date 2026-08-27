# Pins the context ring glyph to every one of its band boundaries.
# Unlike the other two scripts this one asserts and sets an exit code: the bands are
# hand-picked values whose inclusive/exclusive edges would drift silently under a refactor.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-ring-bands.ps1
#        ...-File tests\test-ring-bands.ps1 -Script .\statusline.ps1   (test the local copy)

param([string]$Script = "$HOME\.claude\statusline.ps1")

if (-not (Test-Path $Script)) { throw "Status line script not found: $Script" }

# The block/circle glyphs need a UTF-8 console here too, or every comparison fails.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}

$circle  = [string][char]0x25CB
$quarter = [string][char]0x25D4
$half    = [string][char]0x25D1
$three   = [string][char]0x25D5
$full    = [string][char]0x25CF

# pct, expected glyph, what the row pins down
$cases = @(
    @(0,     $circle,  "zero"),
    @(0.4,   $circle,  "barely used still reads empty"),
    @(9,     $circle,  "top of the empty band, inclusive"),
    @(9.1,   $quarter, "first sliver"),
    @(13,    $quarter, ""),
    @(37.4,  $quarter, "just under the half band"),
    @(37.5,  $half,    "half band opens inclusive"),
    @(50,    $half,    ""),
    @(62.5,  $half,    "half band closes inclusive"),
    @(62.6,  $three,   "just over the half band"),
    @(75,    $three,   ""),
    @(87.4,  $three,   "just under full"),
    @(87.5,  $full,    "full opens exactly here"),
    @(91,    $full,    ""),
    @(100,   $full,    "clamped ceiling"),
    @(142,   $full,    "out of range clamps, never overflows"),
    @(-5,    $circle,  "negative clamps to empty")
)

$inv    = [System.Globalization.CultureInfo]::InvariantCulture
$failed = 0

Write-Host "Testing: $Script`n"
Write-Host ("{0,8}  {1,-7} {2,-7} {3,-6} {4}" -f "pct", "glyph", "expect", "result", "pins")

foreach ($case in $cases) {
    $pct = $case[0]; $want = $case[1]; $note = $case[2]

    # Invariant culture: a comma decimal separator would be invalid JSON.
    $json = '{"model":{"display_name":"X"},"context_window":{"used_percentage":' +
            $pct.ToString($inv) + ',"context_window_size":200000}}'

    $raw   = $json | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script
    $clean = $raw -replace "$([char]27)\[[0-9;]*m", ''

    $got = if ($clean -match '\|\s+(\S)\s+\d+%') { $Matches[1] } else { '?' }
    $ok  = ($got -eq $want)
    if (-not $ok) { $failed++ }

    Write-Host ("{0,8}  {1,-7} {2,-7} {3,-6} {4}" -f
        $pct, $got, $want, $(if ($ok) { "pass" } else { "FAIL" }), $note)
}

Write-Host ""
if ($failed -eq 0) {
    Write-Host "All $($cases.Count) band boundaries pass."
    exit 0
} else {
    Write-Host "$failed of $($cases.Count) FAILED."
    exit 1
}

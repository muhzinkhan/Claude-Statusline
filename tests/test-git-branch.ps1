# Exercises the git branch segment against every repo state it can encounter.
# Creates throwaway repos under $env:TEMP and removes them afterwards.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-git-branch.ps1

param([string]$Script = "$HOME\.claude\statusline.ps1")

if (-not (Test-Path $Script)) { throw "Status line script not found: $Script" }

$root = Join-Path $env:TEMP "statusline-gitcases"
if (Test-Path $root) { Remove-Item $root -Recurse -Force }
New-Item -ItemType Directory -Path $root | Out-Null

function Run($label, $dir) {
    $d = $dir -replace '\\', '/'
    $json = @"
{"model":{"display_name":"Opus 5"},
 "workspace":{"current_dir":"$d"},
 "context_window":{"used_percentage":7.6,"context_window_size":1000000},
 "rate_limits":{"five_hour":{"used_percentage":23.1}}}
"@
    $out = $json | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script
    Write-Host ("{0,-22} {1}" -f $label, $out)
}

try {
    # repo with a commit on a named branch
    $normal = Join-Path $root "normal"
    New-Item -ItemType Directory -Path $normal | Out-Null
    git -C $normal init -q -b feature/status-bar
    git -C $normal -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

    # unborn branch: initialised, no commits yet
    $unborn = Join-Path $root "unborn"
    New-Item -ItemType Directory -Path $unborn | Out-Null
    git -C $unborn init -q -b main

    # detached HEAD
    $detached = Join-Path $root "detached"
    New-Item -ItemType Directory -Path $detached | Out-Null
    git -C $detached init -q -b main
    git -C $detached -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    git -C $detached checkout -q --detach (git -C $detached rev-parse HEAD).Trim()

    # plain directory, not a repo
    $plain = Join-Path $root "plain"
    New-Item -ItemType Directory -Path $plain | Out-Null

    Write-Host "Testing: $Script`n"
    Run "normal branch" $normal
    Run "unborn branch" $unborn
    Run "detached HEAD" $detached
    Run "not a repo"    $plain
    Run "missing dir"   (Join-Path $root "does-not-exist")

    Write-Host @"

Expected:
  normal branch  ->  feature/status-bar in green
  unborn branch  ->  main in green (rev-parse would show nothing here)
  detached HEAD  ->  branch segment omitted
  not a repo     ->  branch segment omitted
  missing dir    ->  branch segment omitted
"@
}
finally {
    if (Test-Path $root) { Remove-Item $root -Recurse -Force }
}

# Dot-sourced by the other Windows scripts. The run is $env:VP_RUN, or the
# one up.ps1 started last ($Runs\current), so each script can run in a
# fresh shell.
Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Skill = Split-Path (Split-Path $PSScriptRoot)
$ToolRepo = (Resolve-Path (Join-Path $Skill '..\..\..')).Path
$Runs = Join-Path ([IO.Path]::GetTempPath()) 'verify-pointy'
$PointyPort = 47397
$EV = $null
if (-not (Get-Variable NoRun -ErrorAction SilentlyContinue)) { $NoRun = $false }

if (-not $env:VP_RUN -and (Test-Path (Join-Path $Runs 'current'))) {
  $env:VP_RUN = (Get-Content -Raw (Join-Path $Runs 'current')).Trim()
}
if (-not $NoRun) {
  if (-not $env:VP_RUN -or -not (Test-Path $env:VP_RUN)) { throw 'no run is up; start one with up.ps1' }
  $VP_RUN = $env:VP_RUN
  $Bin = Join-Path $VP_RUN 'bin'
  $EV = Join-Path $VP_RUN 'evidence'
  $Sock = Join-Path $VP_RUN 'a.sock'
  $PointyHome = Join-Path $VP_RUN 'home'
  $SettingsFile = Join-Path $PointyHome 'settings.json'
  $env:MYGO_AUTOMATION_SESSION = 'verify-pointy-' + (Split-Path -Leaf $VP_RUN)
  # drive records its own input here, so guard does not take it for the user's.
  $env:DRIVE_STAMP = Join-Path $VP_RUN 'input-stamp'
  New-Item -ItemType Directory -Force $EV | Out-Null
}

function Log([string]$msg) {
  Write-Host $msg
  if ($EV) { Add-Content -LiteralPath (Join-Path $EV 'run.log') -Value $msg -Encoding utf8 }
}
function Die([string]$msg) { Log "FAIL: $msg"; throw $msg }
function Get-RunPid([string]$name) {
  $f = Join-Path $VP_RUN "pids\$name"
  if (Test-Path $f) { [int](Get-Content -Raw $f).Trim() }
}

# Drive runs bin\drive.exe and fails on a non-zero exit, unless -Soft.
function Drive {
  $out = & (Join-Path $Bin 'drive.exe') @args
  if ($LASTEXITCODE -ne 0) { Die "drive $($args -join ' ') exited $LASTEXITCODE" }
  $out
}
function Pa {
  $out = & (Join-Path $Bin 'mygo-automation.exe') @args
  if ($LASTEXITCODE -ne 0) { throw "mygo-automation $($args[0]) exited $LASTEXITCODE" }
  $out
}
# Js <window> <script>: evaluates the script in a page of the run's Pointy.
function Js([string]$window, [string]$script) {
  Pa open --socket $Sock | Out-Null
  Pa eval --window $window $script
}
# Win-Of <page>: the automation id of the newest visible window showing that page.
function Win-Of([string]$page) {
  Pa open --socket $Sock | Out-Null
  $line = Pa windows | Where-Object { $_ -match [regex]::Escape($page) -and $_ -notmatch 'hidden' } | Select-Object -Last 1
  if ($line) { ($line -split '\s+')[0] }
}
function Has-Page([string]$page) { [bool](Win-Of $page) }

function Read-Settings { Get-Content -Raw -LiteralPath $SettingsFile | ConvertFrom-Json }

# Wait-Until <seconds> <what> { condition }: polls until the block returns true.
function Wait-Until([double]$secs, [string]$what, [scriptblock]$cond) {
  $end = (Get-Date).AddSeconds($secs)
  while ((Get-Date) -lt $end) {
    try { if (& $cond) { return } } catch {}
    Start-Sleep -Milliseconds 200
  }
  Die "timed out after ${secs}s waiting for $what"
}

# Guard returns once the screen is unlocked and the user has not touched the
# keyboard or mouse for VP_IDLE seconds (30), waiting up to VP_WAIT (900);
# it aborts the run otherwise. Call it before every batch of input.
function Guard {
  $need = if ($env:VP_IDLE) { [double]$env:VP_IDLE } else { 30 }
  $wait = if ($env:VP_WAIT) { [double]$env:VP_WAIT } else { 900 }
  $end = (Get-Date).AddSeconds($wait)
  $idle = 0
  while ((Get-Date) -lt $end) {
    $locked = Drive locked
    $idle = [double](Drive idle)
    if ($locked -eq 'false' -and $idle -ge $need) { return }
    Start-Sleep -Seconds 2
  }
  if ((Drive locked) -ne 'false') { Die 'the screen stayed locked' }
  Die "the user stayed active (idle ${idle}s < ${need}s); not touching the mouse or keyboard"
}

# Mine <x> <y> <pid>...: aborts unless the top window at x,y belongs to one of the pids.
function Mine([int]$x, [int]$y, [int[]]$pids) {
  $o = [int](Drive at $x $y)
  if ($pids -notcontains $o) { Die "the window at $x,$y is pid $o's, not $($pids -join ',')'s; not touching it" }
}

# Shot-Page <page> <name>: saves a screenshot of the newest window showing the page.
function Shot-Page([string]$page, [string]$name) {
  $w = Win-Of $page
  if (-not $w) { Die "no window shows $page" }
  Pa screenshot --window $w (Join-Path $EV "$name.png") | Out-Null
}

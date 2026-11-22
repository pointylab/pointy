# usage: dnd.ps1 [-Repo <checkout>] [-Keep]
# Do Not Disturb on Windows, from a fresh run to down.ps1: toggle DND on in
# the tray, verify shaking and a global shortcut are ignored while it is on,
# then turn DND off and verify shaking starts pointing again.
# Prints PASS/FAIL per check; evidence stays in $VP_RUN\evidence.
param([string]$Repo = '', [switch]$Keep)
$ErrorActionPreference = 'Stop'
$s = Join-Path $PSScriptRoot '..\scripts\win'
$src = if ($Repo) { $Repo } elseif ($env:VP_REPO) { $env:VP_REPO } else { (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path }
$t = (Get-Content -Raw (Join-Path $src 'locales\zh-CN.json') | ConvertFrom-Json).tray
if (-not $t.PSObject.Properties['dnd']) { 'SKIP: this checkout has no Do Not Disturb item'; exit 0 }

$up = & (Join-Path $s 'up.ps1') -Locale zh-CN -Repo $Repo
$env:VP_RUN = ($up | Select-Object -Last 1) -replace '^VP_RUN=', ''
. (Join-Path $s 'env.ps1')

$failed = 0
function Expect([string]$what, [scriptblock]$cond) {
  $ok = $false
  try { $ok = [bool](& $cond) } catch { $what += " ($_)" }
  Log "$(if ($ok) { 'PASS' } else { 'FAIL' }) $what"
  if (-not $ok) { $script:failed++ }
}
function Tray { & (Join-Path $s 'tray.ps1') @args }
function Keys { & (Join-Path $s 'keys.ps1') @args }
function Logged([string]$needle, [int]$tail = 20) {
  [bool](Get-Content -LiteralPath (Join-Path $EV 'run.log') -Tail $tail -Encoding utf8 |
      Where-Object { $_.Contains($needle) })
}
function Overlay-Up { Has-Page 'overlay.html' }

try {
  # 1. DND starts off; clicking it turns it on and saves dnd=true.
  Tray 'before'
  Expect 'DND is unchecked initially' { Logged "[ ] $($t.dnd)" }
  Expect 'settings.json starts with dnd=false' { (Read-Settings).dnd -eq $false }
  Tray 'on' $t.dnd
  Expect 'dnd is saved as true in settings.json' { (Read-Settings).dnd -eq $true }
  Tray 'on-checked'
  Expect 'the tray checks DND' { Logged "[x] $($t.dnd)" }

  # 2. Shaking over the fixture window is ignored while DND is on.
  $fx = & (Join-Path $s 'fixture.ps1') | Select-Object -Last 1 | ConvertFrom-Json
  $fxPid = Get-RunPid fixture
  $cx = [int]($fx.X + $fx.W / 2); $cy = [int]($fx.Y + $fx.H / 2)
  Guard
  Drive focus $fx.HWND | Out-Null
  foreach ($px in ($cx - 70), $cx, ($cx + 70)) { Mine $px $cy @($fxPid) }
  Drive move $cx $cy | Out-Null
  Start-Sleep -Milliseconds 200
  Drive shake $cx $cy | Out-Null
  Start-Sleep -Milliseconds 1200
  Expect 'shaking does not start pointing while DND is on' { -not (Overlay-Up) }
  $errLog = Join-Path $PointyHome 'error.log'
  Expect 'Pointy logs shake-ignored dnd' { (Test-Path $errLog) -and ((Get-Content -Raw $errLog) -match '\[shake-ignored\] dnd') }

  # 3. A bound global shortcut is also ignored while DND is on.
  if ($t.PSObject.Properties['hotkey']) {
    Tray 'hotkey-preset' $t.hotkey 'Ctrl+Alt+P'
    Guard
    Drive focus $fx.HWND | Out-Null
    Mine $cx $cy @($fxPid)
    Drive move $cx $cy | Out-Null
    Keys 'Ctrl+Alt+P' -To fixture
    Start-Sleep -Milliseconds 1200
    Expect 'a global shortcut does not start pointing while DND is on' { -not (Overlay-Up) }
  }

  # 4. Turning DND off restores shaking.
  Tray 'off' $t.dnd
  Expect 'dnd is saved as false in settings.json' { (Read-Settings).dnd -eq $false }
  Tray 'off-checked'
  Expect 'the tray unchecks DND' { Logged "[ ] $($t.dnd)" }
  Guard
  Drive focus $fx.HWND | Out-Null
  foreach ($px in ($cx - 70), $cx, ($cx + 70)) { Mine $px $cy @($fxPid) }
  Drive move $cx $cy | Out-Null
  Start-Sleep -Milliseconds 200
  Drive shake $cx $cy | Out-Null
  Expect 'shaking starts pointing once DND is off' { Wait-Until 5 'the pointing overlay' { Overlay-Up }; $true }
  Start-Sleep -Milliseconds 600
  Drive shotwin $fx.HWND (Join-Path $EV 'after-dnd-pointing.png') -8 | Out-Null
  Keys 'Esc' -To both
  Expect 'Esc ends pointing' { Wait-Until 5 'the overlay to close' { -not (Overlay-Up) }; $true }
} catch {
  Log "FAIL scenario stopped: $_"
  $failed++
} finally {
  if (-not $Keep) { & (Join-Path $s 'down.ps1') | Out-Null }
}
Log "$(if ($failed) { "$failed check(s) failed" } else { 'all checks passed' }); evidence in $EV"
if ($failed) { exit 1 }

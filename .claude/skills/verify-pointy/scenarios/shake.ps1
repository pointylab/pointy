# usage: shake.ps1 [-Repo <checkout>] [-Keep]
# Shake sensitivity on Windows, from a fresh run to down.ps1: turn shake off
# (a hard shake does nothing), set Low (a light shake does nothing, a hard shake
# starts pointing), set High (the same light shake starts pointing), then return
# to Medium. Prints PASS/FAIL per check; evidence stays in $VP_RUN\evidence.
param([string]$Repo = '', [switch]$Keep)
$ErrorActionPreference = 'Stop'
$s = Join-Path $PSScriptRoot '..\scripts\win'
$src = if ($Repo) { $Repo } elseif ($env:VP_REPO) { $env:VP_REPO } else { (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path }
$t = (Get-Content -Raw (Join-Path $src 'locales\zh-CN.json') | ConvertFrom-Json).tray
if (-not $t.PSObject.Properties['shake']) { 'SKIP: this checkout has no shake submenu'; exit 0 }

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
function Logged([string]$needle, [int]$tail = 15) {
  [bool](Get-Content -LiteralPath (Join-Path $EV 'run.log') -Tail $tail -Encoding utf8 |
      Where-Object { $_.Contains($needle) })
}
function Overlay-Up { Has-Page 'overlay.html' }

$fx = $null
$fxPid = 0
$cx = 0; $cy = 0
function Shake-Over([int]$amp) {
  Guard
  Drive focus $fx.HWND | Out-Null
  $pad = [Math]::Max($amp + 10, 70)
  foreach ($px in ($cx - $pad), $cx, ($cx + $pad)) { Mine $px $cy @($fxPid) }
  Drive move $cx $cy | Out-Null
  Start-Sleep -Milliseconds 200
  Drive shake $cx $cy $amp | Out-Null
}

try {
  $fx = & (Join-Path $s 'fixture.ps1') | Select-Object -Last 1 | ConvertFrom-Json
  $fxPid = Get-RunPid fixture
  $cx = [int]($fx.X + $fx.W / 2); $cy = [int]($fx.Y + $fx.H / 2)

  # 1. Off: even a hard shake (amp 60 -> span 120) does not start pointing.
  Tray 'off' $t.shake $t.shakeOff
  Expect 'shake is saved as false in settings.json' { (Read-Settings).shake -eq $false }
  Tray 'off-checked' $t.shake
  Expect 'the submenu checks Off' { Logged "[x] $($t.shakeOff)" }
  Shake-Over 60
  Start-Sleep -Milliseconds 1200
  Expect 'a hard shake does nothing when shake is Off' { -not (Overlay-Up) }

  # 2. Low (requires >= 60 per leg): light shake (amp 20 -> span 40) is ignored;
  #    hard shake (amp 60 -> span 120) starts pointing.
  Tray 'low' $t.shake $t.shakeLow
  Expect 'shake=true and shakeLevel=low in settings.json' {
    $st = Read-Settings; ($st.shake -eq $true) -and ($st.shakeLevel -eq 'low')
  }
  Tray 'low-checked' $t.shake
  Expect 'the submenu checks Low' { Logged "[x] $($t.shakeLow)" }
  Shake-Over 20
  Start-Sleep -Milliseconds 1200
  Expect 'a light shake does not trigger at Low sensitivity' { -not (Overlay-Up) }
  Shake-Over 60
  Expect 'a hard shake triggers at Low sensitivity' { Wait-Until 5 'the pointing overlay' { Overlay-Up }; $true }
  Start-Sleep -Milliseconds 600
  Drive shotwin $fx.HWND (Join-Path $EV 'low-pointing.png') -8 | Out-Null
  Keys 'Esc' -To both
  Expect 'Esc ends pointing after Low' { Wait-Until 5 'the overlay to close' { -not (Overlay-Up) }; $true }

  # 3. High (requires >= 28 per leg): the same light shake (amp 20 -> span 40)
  #    now starts pointing once the 1.5 s shake cooldown has passed.
  Tray 'high' $t.shake $t.shakeHigh
  Expect 'shake=true and shakeLevel=high in settings.json' {
    $st = Read-Settings; ($st.shake -eq $true) -and ($st.shakeLevel -eq 'high')
  }
  Tray 'high-checked' $t.shake
  Expect 'the submenu checks High' { Logged "[x] $($t.shakeHigh)" }
  Start-Sleep -Milliseconds 1700
  Shake-Over 20
  Expect 'a light shake triggers at High sensitivity' { Wait-Until 5 'the pointing overlay' { Overlay-Up }; $true }
  Start-Sleep -Milliseconds 600
  Drive shotwin $fx.HWND (Join-Path $EV 'high-pointing.png') -8 | Out-Null
  Keys 'Esc' -To both
  Expect 'Esc ends pointing after High' { Wait-Until 5 'the overlay to close' { -not (Overlay-Up) }; $true }

  # 4. Medium: saved and checked.
  Tray 'medium' $t.shake $t.shakeMedium
  Expect 'shake=true and shakeLevel=medium in settings.json' {
    $st = Read-Settings; ($st.shake -eq $true) -and ($st.shakeLevel -eq 'medium')
  }
  Tray 'medium-checked' $t.shake
  Expect 'the submenu checks Medium' { Logged "[x] $($t.shakeMedium)" }
} catch {
  Log "FAIL scenario stopped: $_"
  $failed++
} finally {
  if (-not $Keep) { & (Join-Path $s 'down.ps1') | Out-Null }
}
Log "$(if ($failed) { "$failed check(s) failed" } else { 'all checks passed' }); evidence in $EV"
if ($failed) { exit 1 }

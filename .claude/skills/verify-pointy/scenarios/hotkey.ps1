# usage: hotkey.ps1 [-Repo <checkout>] [-Keep]
# The keyboard shortcut (#39) on Windows, from a fresh run to down.ps1:
# choose a preset in the tray, start pointing with it over the run's own
# window, record a custom one, and see what a shortcut another app holds
# does. Prints PASS/FAIL per check; evidence stays in $VP_RUN\evidence.
param([string]$Repo = '', [switch]$Keep)
$ErrorActionPreference = 'Stop'
$s = Join-Path $PSScriptRoot '..\scripts\win'
$src = if ($Repo) { $Repo } elseif ($env:VP_REPO) { $env:VP_REPO } else { (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path }
$t = (Get-Content -Raw (Join-Path $src 'locales\zh-CN.json') | ConvertFrom-Json).tray
if (-not $t.PSObject.Properties['hotkey']) { 'SKIP: this checkout has no keyboard shortcut (no tray.hotkey text)'; exit 0 }
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
function Overlay-Up { Has-Page 'overlay.html' }

$pointy = Get-RunPid pointy
try {
  # 1. A preset from the tray is saved and bound.
  Tray 'preset' $t.hotkey 'Ctrl+Alt+P'
  Expect 'the preset is saved in settings.json' { (Read-Settings).hotkey -eq 'CmdOrCtrl+Alt+P' }
  Tray 'preset-checked' $t.hotkey
  Expect 'the tray checks the preset' { (Get-Content (Join-Path $EV 'run.log') -Tail 12) -match '\[x\] Ctrl\+Alt\+P' }

  # 2. The shortcut starts pointing over the run's own window; Esc ends it.
  $fx = & (Join-Path $s 'fixture.ps1') | Select-Object -Last 1 | ConvertFrom-Json
  $cx = [int]($fx.X + $fx.W / 2); $cy = [int]($fx.Y + $fx.H / 2)
  Guard
  Mine $cx $cy @(Get-RunPid fixture)
  Drive move $cx $cy | Out-Null
  Keys 'Ctrl+Alt+P' -To fixture
  Expect 'Ctrl+Alt+P starts pointing' { Wait-Until 5 'the pointing overlay' { Overlay-Up }; $true }
  Start-Sleep -Milliseconds 600
  Drive shotwin $fx.HWND (Join-Path $EV 'preset-pointing.png') -8 | Out-Null
  Keys 'Esc' -To both
  Expect 'Esc ends pointing' { Wait-Until 5 'the overlay to close' { -not (Overlay-Up) }; $true }

  # 3. Custom…: the recorder takes focus, records a chord, Enter saves it.
  Tray 'custom' $t.hotkey $t.hotkeyCustom
  Expect 'the recorder opens' { Wait-Until 5 'the recorder' { Has-Page 'notice.html' }; $true }
  Start-Sleep -Milliseconds 500
  Expect 'the recorder has the keyboard focus' { [int](Drive front) -eq $pointy }
  $rw = Win-Of 'notice.html'
  Shot-Page 'notice.html' 'custom-open'
  Log "recorder shows: $(Js $rw "return document.getElementById('keys').textContent")"
  Keys 'Ctrl+Shift+K'
  Start-Sleep -Milliseconds 300
  Expect 'the recorder shows Ctrl+Shift+K' { (Js $rw "return document.getElementById('keys').textContent") -eq 'Ctrl+Shift+K' }
  Shot-Page 'notice.html' 'custom-recorded'
  Keys 'Enter'
  Expect 'Enter saves and closes the recorder' { Wait-Until 5 'the recorder to close' { -not (Has-Page 'notice.html') }; $true }
  Expect 'the custom shortcut is saved in settings.json' { (Read-Settings).hotkey -eq 'Ctrl+Shift+K' }
  Tray 'custom-checked' $t.hotkey
  Expect 'the tray lists and checks Ctrl+Shift+K' { (Get-Content (Join-Path $EV 'run.log') -Tail 12) -match '\[x\] Ctrl\+Shift\+K' }

  # 4. The custom shortcut starts pointing too.
  Guard
  Drive focus $fx.HWND | Out-Null
  Mine $cx $cy @(Get-RunPid fixture)
  Drive move $cx $cy | Out-Null
  Keys 'Ctrl+Shift+K' -To fixture
  Expect 'Ctrl+Shift+K starts pointing' { Wait-Until 5 'the pointing overlay' { Overlay-Up }; $true }
  Keys 'Esc' -To both
  Wait-Until 5 'the overlay to close' { -not (Overlay-Up) }

  # 5. A shortcut another app holds: the recorder never sees it, and a preset
  #    that is taken is reported, not saved as bound.
  $hold = Start-Process pwsh -PassThru -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-File', (Join-Path $s 'hold-hotkey.ps1'), 5, 0x20, (Join-Path $VP_RUN 'holder.out')   # Alt+Shift+Space
  Set-Content -LiteralPath (Join-Path $VP_RUN 'pids\holder') -Value $hold.Id
  Wait-Until 15 'the other app to hold Alt+Shift+Space' { (Get-Content -Raw (Join-Path $VP_RUN 'holder.out')) -match 'held' }
  Tray 'custom-taken' $t.hotkey $t.hotkeyCustom
  Wait-Until 5 'the recorder' { Has-Page 'notice.html' }
  Start-Sleep -Milliseconds 500
  $rw = Win-Of 'notice.html'
  Keys 'Alt+Shift+Space'
  Start-Sleep -Milliseconds 300
  Expect 'the recorder does not see a chord another app holds' { (Js $rw "return document.getElementById('keys').textContent") -ne 'Alt+Shift+Space' }
  Shot-Page 'notice.html' 'custom-taken'
  Keys 'Esc'
  Expect 'Esc cancels the recorder' { Wait-Until 5 'the recorder to close' { -not (Has-Page 'notice.html') }; $true }
  Expect 'cancelling keeps Ctrl+Shift+K' { (Read-Settings).hotkey -eq 'Ctrl+Shift+K' }
  Tray 'preset-taken' $t.hotkey 'Alt+Shift+Space'
  Start-Sleep -Milliseconds 500
  Expect 'Pointy logs that Alt+Shift+Space is taken' { (Get-Content -Raw (Join-Path $PointyHome 'error.log')) -match 'shortcut.*cannot register "Alt\+Shift\+Space"' }
  Stop-Process -Id $hold.Id -ErrorAction SilentlyContinue
} catch {
  Log "FAIL scenario stopped: $_"
  $failed++
} finally {
  if (-not $Keep) { & (Join-Path $s 'down.ps1') | Out-Null }
}
Log "$(if ($failed) { "$failed check(s) failed" } else { 'all checks passed' }); evidence in $EV"
if ($failed) { exit 1 }

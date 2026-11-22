# usage: language.ps1 [-Repo <checkout>] [-Keep]
# Switching languages through the tray on Windows, from a fresh run to down.ps1:
# verify the Chinese menu, switch to English, check the English menu and a newly
# opened English notice, switch back to Chinese, and return to Same as System.
# Prints PASS/FAIL per check; evidence stays in $VP_RUN\evidence.
param([string]$Repo = '', [switch]$Keep)
$ErrorActionPreference = 'Stop'
$s = Join-Path $PSScriptRoot '..\scripts\win'
$src = if ($Repo) { $Repo } elseif ($env:VP_REPO) { $env:VP_REPO } else { (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path }
$zh = Get-Content -Raw (Join-Path $src 'locales\zh-CN.json') | ConvertFrom-Json
$en = Get-Content -Raw (Join-Path $src 'locales\en.json') | ConvertFrom-Json
if (-not $zh.PSObject.Properties['language']) { 'SKIP: this checkout has no language menu'; exit 0 }

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
function Logged([string]$needle, [int]$tail = 25) {
  [bool](Get-Content -LiteralPath (Join-Path $EV 'run.log') -Tail $tail -Encoding utf8 |
      Where-Object { $_.Contains($needle) })
}

try {
  # 1. Starts in Chinese.
  Tray 'zh'
  Expect 'the initial tray menu is in Chinese' {
    (Logged $zh.tray.shake) -and (Logged $zh.tray.dnd) -and (Logged $zh.language.menu) -and (Logged $zh.tray.quit)
  }

  # 2. Switch to English via the tray.
  Tray 'to-en' $zh.language.menu $en.language.self
  Expect 'locale is saved as en in settings.json' { (Read-Settings).locale -eq 'en' }

  # 3. Tray menu and submenu update to English at once.
  Tray 'en' $en.language.menu
  Expect 'the tray menu switches to English' {
    (Logged $en.tray.shake) -and (Logged $en.tray.guide) -and (Logged $en.tray.dnd) -and (Logged $en.tray.quit)
  }
  Expect 'the Language submenu checks English' { Logged "[x] $($en.language.self)" 15 }

  # 4. A notice opened after the switch uses English.
  Tray 'en-guide' $en.tray.guide
  Expect 'the welcome notice opens' { Wait-Until 5 'the notice' { Has-Page 'notice.html' }; $true }
  Start-Sleep -Milliseconds 400
  $nw = Win-Of 'notice.html'
  Shot-Page 'notice.html' 'en-notice'
  $noticeText = Js $nw 'return document.getElementById("box").innerText'
  Log "English notice text: $($noticeText -replace '\r?\n', ' | ')"
  Expect 'the notice shows English welcome text' {
    $noticeText.Contains($en.welcome.title) -and $noticeText.Contains('Shake the mouse')
  }
  Js $nw 'setTimeout(() => document.getElementById("x").click()); return "ok"' | Out-Null
  Expect 'the notice closes' { Wait-Until 5 'the notice to close' { -not (Has-Page 'notice.html') }; $true }

  # 5. Switch back to Chinese.
  Tray 'to-zh' $en.language.menu $zh.language.self
  Expect 'locale is saved as zh-CN in settings.json' { (Read-Settings).locale -eq 'zh-CN' }
  Tray 'zh-again'
  Expect 'the tray menu returns to Chinese' { (Logged $zh.tray.shake) -and (Logged $zh.tray.quit) }

  # 6. Return to Same as System clears locale from settings.json.
  Tray 'to-system' $zh.language.menu $zh.language.system
  Expect 'locale leaves settings.json after Same as System' {
    $st = Read-Settings
    (-not $st.PSObject.Properties['locale']) -or (-not $st.locale)
  }
} catch {
  Log "FAIL scenario stopped: $_"
  $failed++
} finally {
  if (-not $Keep) { & (Join-Path $s 'down.ps1') | Out-Null }
}
Log "$(if ($failed) { "$failed check(s) failed" } else { 'all checks passed' }); evidence in $EV"
if ($failed) { exit 1 }

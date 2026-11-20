# usage: ask.ps1 [-Repo <checkout>] [-Keep]
# The main flow on Windows against DSH and the mock model, from a fresh run to
# down.ps1: shake over the run's own window, click its paragraph, ask from the
# card in full mode and read the answer; then ask again, close the card
# mid-task into a pill, follow it to done and click it back into a card.
# Prints PASS/FAIL per check; evidence stays in $VP_RUN\evidence.
param([string]$Repo = '', [switch]$Keep)
$ErrorActionPreference = 'Stop'
$s = Join-Path $PSScriptRoot '..\scripts\win'
$dshCheck = if ($env:DSH) { $env:DSH } else { 'dsh.cmd' }
if (-not (Get-Command $dshCheck -ErrorAction SilentlyContinue)) {
  'SKIP: no dsh on PATH (or $env:DSH)'
  exit 0
}
$up = & (Join-Path $s 'up.ps1') -Locale zh-CN -Repo $Repo -Dsh
$env:VP_RUN = ($up | Select-Object -Last 1) -replace '^VP_RUN=', ''
. (Join-Path $s 'env.ps1')

$failed = 0
function Expect([string]$what, [scriptblock]$cond) {
  $ok = $false
  try { $ok = [bool](& $cond) } catch { $what += " ($_)" }
  Log "$(if ($ok) { 'PASS' } else { 'FAIL' }) $what"
  if (-not $ok) { $script:failed++ }
}
function Logged([string]$needle, [int]$tail = 30) {
  [bool](Get-Content -LiteralPath (Join-Path $EV 'run.log') -Tail $tail -Encoding utf8 |
      Where-Object { $_.Contains($needle) })
}
function Page-Has([string]$win, [string]$id, [string]$text) {
  $lit = ConvertTo-Json -InputObject $text -Compress
  Js $win "if (!document.getElementById('$id').innerText.includes($lit)) throw 'no'" | Out-Null
  $true
}
function Mock-Got([string[]]$parts) {
  $file = Join-Path $EV 'mock.jsonl'
  if (-not (Test-Path $file)) { return $false }
  foreach ($line in Get-Content -LiteralPath $file -Encoding utf8) {
    if (-not $line.Trim()) { continue }
    $entry = $line | ConvertFrom-Json
    if (-not $entry.PSObject.Properties['body'] -or -not $entry.body.PSObject.Properties['messages']) { continue }
    $msgs = @($entry.body.messages)
    if ($msgs.Count -eq 0) { continue }
    $last = ConvertTo-Json -InputObject $msgs[-1] -Depth 20 -Compress
    $all = $true
    foreach ($p in $parts) {
      if (-not $last.Contains($p)) { $all = $false; break }
    }
    if ($all) { return $true }
  }
  return $false
}

$question = '这段话在说什么'
$paragraph = 'shake the mouse, point at anything on screen'

try {
  # 1. A shake over the window starts pointing; a click opens a card that quotes it.
  $cw = $null
  try { $cw = & (Join-Path $s 'pick.ps1') 'first' | Select-Object -Last 1 } catch {}
  Expect 'a shake and a click open a card' { [bool]$cw }
  if ($cw) {
    Expect 'the card quotes the paragraph pointed at' { Logged $paragraph 5 }

    # 2. Full mode: a search step, the answer, DSH's title, and what the model got.
    try { & (Join-Path $s 'ask.ps1') $cw 'first' $question } catch { Log "(ask.ps1 failed: $_)" }
    Expect 'the card shows the search step' { Logged '正在搜索「pointy 指认工具」' 5 }
    Expect 'the card shows the answer' { Page-Has $cw 'thread' '这是一段模拟回答。' }
    Expect "the card takes DSH's title" { Logged 'card title: Mock 标题' 3 }
    Expect 'the model got the question and the paragraph' { Mock-Got @($question, $paragraph) }

    # 3. Closing a card mid-task keeps it as a pill, which turns done and opens the card again.
    $cw = $null
    try { $cw = & (Join-Path $s 'pick.ps1') 'kept' | Select-Object -Last 1 } catch {}
    if (-not $cw) {
      Log 'FAIL a second pick opens a card'
      $failed++
    } else {
      try { & (Join-Path $s 'ask.ps1') $cw 'kept' $question -Keep } catch { Log "(ask.ps1 -Keep failed: $_)" }
      Expect 'closing the card mid-task shows a running pill' { Logged 'pill while running: pill run' 6 }
      Expect 'the pill turns done' { Logged 'pill when done: pill done' 4 }
      Expect "the pill keeps DSH's title" {
        [bool](Get-Content -LiteralPath (Join-Path $EV 'run.log') -Tail 4 -Encoding utf8 |
            Where-Object { $_ -match 'pill when done: .*Mock 标题' })
      }
      # The click closes the pill window, so it waits until eval has returned.
      Js (Win-Of 'pill.html') 'setTimeout(() => [...document.querySelectorAll(".pill:not(.out)")].at(-1).click()); return "ok"' | Out-Null
      Expect 'clicking the pill brings the card back' {
        $end = (Get-Date).AddSeconds(5)
        while ((Get-Date) -lt $end) {
          if (Has-Page 'card.html') { return $true }
          Start-Sleep -Milliseconds 200
        }
        $false
      }
      Shot-Page 'card.html' 'kept-restored'
    }
  }
} catch {
  Log "FAIL scenario stopped: $_"
  $failed++
} finally {
  if (-not $Keep) { & (Join-Path $s 'down.ps1') | Out-Null }
}
Log "$(if ($failed) { "$failed check(s) failed" } else { 'all checks passed' }); evidence in $EV"
if ($failed) { exit 1 }

# usage: pick.ps1 <name>   opens the run's fixture window, shakes the mouse
# over it and clicks its first paragraph; prints the card's window id.
# Moves the mouse only over that fixture window.
param([Parameter(Mandatory, Position = 0)][string]$Name)
. (Join-Path $PSScriptRoot 'env.ps1')

$fx = & (Join-Path $PSScriptRoot 'fixture.ps1') | Select-Object -Last 1 | ConvertFrom-Json
$fxPid = Get-RunPid fixture
$pointyPid = Get-RunPid pointy
$x = [Math]::Max([int]$fx.X + 80, [Math]::Min([int]$fx.X + 200, [int]$fx.X + [int]$fx.W - 80))
$y = [Math]::Max([int]$fx.Y + 50, [Math]::Min([int]$fx.Y + 80, [int]$fx.Y + [int]$fx.H - 40))

foreach ($px in ($x - 70), $x, ($x + 70)) { Mine $px $y @($fxPid) }

# The screenshot shows only the fixture's rect, and only when no other app's
# window covers any of it, so it never captures the user's windows.
$shoot = $true
$stepX = [Math]::Max(1, [int](([int]$fx.W - 10) / 6))
$stepY = [Math]::Max(1, [int](([int]$fx.H - 10) / 5))
for ($gx = [int]$fx.X + 5; $gx -le [int]$fx.X + [int]$fx.W - 5; $gx += $stepX) {
  for ($gy = [int]$fx.Y + 5; $gy -le [int]$fx.Y + [int]$fx.H - 5; $gy += $stepY) {
    $o = [int](Drive at $gx $gy)
    if ($o -ne $fxPid -and $o -ne $pointyPid) { $shoot = $false; break }
  }
  if (-not $shoot) { break }
}

Guard
Drive move $x $y | Out-Null
Start-Sleep -Milliseconds 200
Drive shake $x $y | Out-Null
Wait-Until 5 'the pointing overlay' { Has-Page 'overlay.html' }
Start-Sleep -Milliseconds 600
$ow = Win-Of 'overlay.html'
Log "pointing at $x,${y}: $(Js $ow 'return document.getElementById("what").textContent')"
if ($shoot) {
  # Inside the window's visible frame: its edge and rounded corners still
  # show a few pixels of whatever lies behind it.
  Drive shotwin $fx.HWND (Join-Path $EV "$Name-pointing.png") -8 | Out-Null
} else {
  Log "no $Name-pointing.png: another app's window covers part of the fixture"
}
Mine $x $y @($fxPid, $pointyPid)
Drive click $x $y | Out-Null
Wait-Until 10 'a card' { Has-Page 'card.html' }
$cw = Win-Of 'card.html'
Wait-Until 15 "the card's sessions" {
  Js $cw 'if (["\u2026", ""].includes(document.getElementById("target-label").textContent)) throw "loading"' 2>$null | Out-Null
  $true
}
Log "card ${cw}: $(Js $cw 'return window.mygo.call("Card.Init").then(i => ({ method: i.grab.method, text: i.grab.text, note: i.grab.note }))')"
Pa screenshot --window $cw (Join-Path $EV "$Name-card.png") | Out-Null
$cw

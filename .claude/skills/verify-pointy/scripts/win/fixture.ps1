# usage: fixture.ps1   opens the run's own window with fixture.txt in a text
# box (a WinForms window of a pwsh of the run's), brings it to the front and
# prints its HWND. Pointing and global shortcuts are tried over it, so input
# lands in a window of the run's, never in the user's apps. Notepad is no
# fixture on Windows 11: it opens files as tabs of a window the user may own.
. (Join-Path $PSScriptRoot 'env.ps1')
$old = Get-RunPid fixture
if ($old -and (Get-Process -Id $old -ErrorAction SilentlyContinue)) { Stop-Process -Id $old -Force }
$p = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList @(
  '-NoProfile', '-STA', '-File', (Join-Path $PSScriptRoot 'fixture-window.ps1'), '-Text', (Join-Path $Skill 'fixture.txt'))
Set-Content -LiteralPath (Join-Path $VP_RUN 'pids\fixture') -Value $p.Id
$h = $null
Wait-Until 20 'the fixture window' {
  $script:h = Drive windows $p.Id | ConvertFrom-Json | Where-Object Title -eq 'verify-pointy fixture' | Select-Object -First 1
  [bool]$script:h
}
Guard
if ((Drive focus $h.HWND) -ne 'true') { Die 'the fixture window would not come to the front' }
Log "fixture window $($h.HWND) (pid $($p.Id)) at $($h.X),$($h.Y) $($h.W)x$($h.H)"
$h | ConvertTo-Json -Compress

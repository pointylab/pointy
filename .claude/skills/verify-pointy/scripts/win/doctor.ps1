# usage: doctor.ps1   read-only: is this run's instance worth driving?
. (Join-Path $PSScriptRoot 'env.ps1')
$bad = $false
function Check([string]$what, [scriptblock]$cond) {
  $ok = $false
  try { $ok = [bool](& $cond) } catch {}
  if ($ok) { "ok   $what" } else { "FAIL $what"; $script:bad = $true }
}
$pointy = Get-RunPid pointy
Check "Pointy is running (pid $pointy)" { Get-Process -Id $pointy -ErrorAction Stop }
Check "port $PointyPort belongs to this run's Pointy" {
  (Get-NetTCPConnection -LocalPort $PointyPort -State Listen -ErrorAction Stop).OwningProcess -contains $pointy
}
Check 'the automation socket answers' { Pa open --socket $Sock | Out-Null; $true }
Check "Pointy is a build of this run's checkout" { (Get-Item (Join-Path $Bin 'Pointy.exe')).LastWriteTime -gt (Get-Item (Join-Path $VP_RUN 'pids')).CreationTime.AddMinutes(-30) }
Check 'the screen is unlocked' { (Drive locked) -eq 'false' }
Check 'the tray icon is up (MyGoApp window)' { (Drive windows $pointy -all | ConvertFrom-Json | Where-Object Class -eq 'MyGoApp') }
"user idle for $(Drive idle)s; settings: $((Get-Content -Raw $SettingsFile) -replace '\s+', ' ')"
$log = Join-Path $PointyHome 'error.log'
if (Test-Path $log) { "error.log: $((Get-Content $log -Tail 3) -join ' | ')" }
if ($bad) { exit 1 }

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
if ($WithDsh) {
  $mock = Get-RunPid mock
  $dsh = Get-RunPid dsh
  Check "mock is running (pid $mock)" { $mock -and (Get-Process -Id $mock -ErrorAction Stop) }
  Check "DSH is running (pid $dsh)" { $dsh -and (Get-Process -Id $dsh -ErrorAction Stop) }
  Check "port $MockPort belongs to this run's mock" {
    if (-not $mock) { return $false }
    $tree = @(Get-Tree $mock)
    [bool]((Get-NetTCPConnection -LocalPort $MockPort -State Listen -ErrorAction Stop).OwningProcess | Where-Object { $tree -contains $_ })
  }
  Check "port $DshPort belongs to this run's DSH" {
    if (-not $dsh) { return $false }
    $tree = @(Get-Tree $dsh)
    [bool]((Get-NetTCPConnection -LocalPort $DshPort -State Listen -ErrorAction Stop).OwningProcess | Where-Object { $tree -contains $_ })
  }
  Check 'the plugin connected to Pointy' {
    $errLog = Join-Path $PointyHome 'error.log'
    (Test-Path $errLog) -and ((Get-Content -Raw -LiteralPath $errLog) -match 'dsh-ui')
  }
}
Check 'the automation socket answers' { Pa open --socket $Sock | Out-Null; $true }
Check "Pointy is a build of this run's checkout" { (Get-Item (Join-Path $Bin 'Pointy.exe')).LastWriteTime -gt (Get-Item (Join-Path $VP_RUN 'pids')).CreationTime.AddMinutes(-30) }
Check 'the screen is unlocked' { (Drive locked) -eq 'false' }
Check 'the tray icon is up (MyGoApp window)' { (Drive windows $pointy -all | ConvertFrom-Json | Where-Object Class -eq 'MyGoApp') }
"user idle for $(Drive idle)s; settings: $((Get-Content -Raw $SettingsFile) -replace '\s+', ' ')"
$log = Join-Path $PointyHome 'error.log'
if (Test-Path $log) { "error.log: $((Get-Content $log -Tail 3) -join ' | ')" }
if ($bad) { exit 1 }

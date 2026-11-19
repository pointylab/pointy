# usage: keys.ps1 <combo> [-To pointy|fixture|both]
# Presses a key combination, as Ctrl+Alt+K or Esc, with real input. drive
# sends nothing unless the foreground window belongs to this run's Pointy
# (or its fixture window, with -To), so no key reaches the user's apps.
param([Parameter(Mandatory)][string]$Combo, [ValidateSet('pointy', 'fixture', 'both')][string]$To = 'pointy')
. (Join-Path $PSScriptRoot 'env.ps1')
$pids = switch ($To) {
  'pointy' { @(Get-RunPid pointy) }
  'fixture' { @(Get-RunPid fixture) }
  'both' { @(Get-RunPid pointy; Get-RunPid fixture) }
}
if (-not $pids -or $null -in $pids) { Die "no $To process in this run" }
Guard
$front = Drive front
Drive keys $Combo @pids | Out-Null
Log "pressed $Combo in pid $front's window"

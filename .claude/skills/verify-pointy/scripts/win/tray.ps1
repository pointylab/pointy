# usage: tray.ps1 <name> [item [subitem]]
# Opens the run's tray menu as a right click on the icon does, logs its
# items (and the submenu's), saves <name>-tray.png, then chooses item >
# subitem with real clicks, or closes the menu. drive checks that every
# point it clicks is a menu of this run's Pointy.
param([Parameter(Mandatory)][string]$Name, [string]$Item, [string]$Subitem)
. (Join-Path $PSScriptRoot 'env.ps1')
$pointy = Get-RunPid pointy
$rest = @(@($Item, $Subitem) | Where-Object { $_ })
Guard
$res = Drive tray $pointy -shot (Join-Path $EV "$Name-tray.png") @rest | ConvertFrom-Json
function Show-Items($items) {
  ($items | ForEach-Object {
    if ($_.Separator) { '  ----' }
    else { '  ' + $(if ($_.Checked) { '[x] ' } else { '[ ] ' }) + $_.Text + $(if ($_.Submenu) { ' >' } else { '' }) + $(if ($_.Disabled) { ' (disabled)' } else { '' }) }
  }) -join "`n"
}
Log "tray menu ($Name):`n$(Show-Items $res.Menu)"
if ($res.Submenu) { Log "submenu `"$Item`":`n$(Show-Items $res.Submenu)" }
if ($res.Chose) { Log "chose $($res.Chose)"; Start-Sleep -Milliseconds 500 }

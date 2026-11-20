# usage: down.ps1   stops what this run started, by the pids it recorded,
# with their child processes (WebView2, DSH, mock), and removes the scratch
# homes, the builds and the socket. $VP_RUN\evidence stays.
. (Join-Path $PSScriptRoot 'env.ps1')

# Stop DSH before Pointy so the plugin does not try to respawn Pointy as its peer exits.
$pidFiles = @(Get-ChildItem (Join-Path $VP_RUN 'pids') -File -ErrorAction SilentlyContinue |
    Sort-Object { if ($_.Name -eq 'dsh') { 0 } else { 1 } }, Name)
foreach ($f in $pidFiles) {
  $root = [int](Get-Content -Raw $f.FullName).Trim()
  if (-not (Get-Process -Id $root -ErrorAction SilentlyContinue)) { continue }
  $all = @(Get-Tree $root)
  Stop-Process -Id $all -Force -ErrorAction SilentlyContinue
  Log "stopped $($f.Name) ($($all -join ','))"
}
try { Pa close | Out-Null } catch {}
Start-Sleep -Milliseconds 500
# Pointy's own account of the run stays with the evidence.
foreach ($f in 'settings.json', 'error.log', 'pet.log') {
  $src = Join-Path $PointyHome $f
  if (Test-Path $src) { Copy-Item -LiteralPath $src (Join-Path $EV "pointy-$f") -Force }
}
foreach ($p in $HomeDir, $DshHome, (Join-Path $VP_RUN 'ws'), $Bin, $Sock, (Join-Path $VP_RUN 'pids')) {
  Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
}
Remove-Item -Path (Join-Path $VP_RUN '*.tgz') -Force -ErrorAction SilentlyContinue
$cur = Join-Path $Runs 'current'
if ((Test-Path $cur) -and (Get-Content -Raw $cur).Trim() -eq $VP_RUN) { Remove-Item $cur }
Log "down; evidence in $EV"

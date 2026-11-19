# usage: up.ps1 [-Locale zh-CN|en|''] [-Repo <checkout>]
# Builds a checkout (this one, or -Repo) and starts its e2e build of Pointy
# on port 47397 with a scratch POINTY_HOME and an automation socket. Prints
# the run directory; later scripts find it through $Runs\current.
param([string]$Locale = '', [string]$Repo = '')
$NoRun = $true
. (Join-Path $PSScriptRoot 'env.ps1')
if (-not $Repo) { $Repo = if ($env:VP_REPO) { $env:VP_REPO } else { $ToolRepo } }
$Repo = (Resolve-Path $Repo).Path

if (Get-NetTCPConnection -LocalPort $PointyPort -State Listen -ErrorAction SilentlyContinue) {
  throw "port $PointyPort is taken; another run may be up (down.ps1 it) or something else owns it"
}
foreach ($tool in 'go', 'node') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not on PATH" }
}

New-Item -ItemType Directory -Force $Runs | Out-Null
$env:VP_RUN = Join-Path $Runs (Get-Date -Format 'yyyyMMdd-HHmmss')
New-Item -ItemType Directory -Force $env:VP_RUN | Out-Null
$NoRun = $false
. (Join-Path $PSScriptRoot 'env.ps1')
New-Item -ItemType Directory -Force $Bin, (Join-Path $VP_RUN 'pids'), $PointyHome | Out-Null
Set-Content -LiteralPath (Join-Path $Runs 'current') -Value $VP_RUN -Encoding utf8
Log "run $VP_RUN, building $Repo"

$build = Join-Path $VP_RUN 'build.log'
function Build([string]$dir, [string[]]$cmd) {
  Push-Location $dir
  try {
    & $cmd[0] @($cmd | Select-Object -Skip 1) *>> $build
    if ($LASTEXITCODE -ne 0) { Die "$($cmd -join ' ') failed in $dir, see $build" }
  } finally { Pop-Location }
}
if (-not (Test-Path (Join-Path $Repo 'node_modules'))) { Build $Repo @('npm.cmd', 'ci') }  # npm.ps1 reads its own command line, which splatting garbles
# The pages carry their texts, so a change to locales needs this step too.
Build $Repo @('node', 'tools/build.ts')
$desk = Join-Path $Repo 'desktop'
$env:CGO_ENABLED = '0'
Build $desk @('go', 'build', '-tags', 'e2e', '-ldflags', '-H windowsgui', '-o', (Join-Path $Bin 'Pointy.exe'), '.')
Build $desk @('go', 'build', '-o', (Join-Path $Bin 'mygo-automation.exe'), 'github.com/egoist/mygo/plugins/automation/cmd/mygo-automation')
# drive comes from the scripts' own checkout: -Repo may predate it.
Build (Join-Path $ToolRepo 'desktop') @('go', 'build', '-o', (Join-Path $Bin 'drive.exe'), './cmd/drive')

# welcomedVersion is the version Pointy reads from the checkout's package.json,
# so neither the full-screen intro nor the welcome covers the screen at start.
$version = (Get-Content -Raw (Join-Path $Repo 'package.json') | ConvertFrom-Json).version
[ordered]@{ dnd = $false; shake = $true; shakeLevel = 'medium'; welcomed = $true; welcomedVersion = $version; locale = $Locale } |
  ConvertTo-Json | Set-Content -LiteralPath $SettingsFile -Encoding utf8

$env:POINTY_HOME = $PointyHome
$env:POINTY_PORT = "$PointyPort"
$env:POINTY_ROOT = Join-Path $Repo 'build'
$env:MYGO_AUTOMATION = $Sock
# No redirection: it would hand Pointy this script's output handles, and a
# caller reading them would wait for Pointy to exit. Pointy logs to its home.
$p = Start-Process (Join-Path $Bin 'Pointy.exe') -PassThru
Set-Content -LiteralPath (Join-Path $VP_RUN 'pids\pointy') -Value $p.Id
Wait-Until 30 "Pointy on $PointyPort" {
  (Get-NetTCPConnection -LocalPort $PointyPort -State Listen -ErrorAction SilentlyContinue).OwningProcess -contains $p.Id
}
Wait-Until 15 'the automation socket' { Pa open --socket $Sock | Out-Null; $true }
Log "up: pointy=$($p.Id) locale=$(if ($Locale) { $Locale } else { 'system' })"
"VP_RUN=$VP_RUN"

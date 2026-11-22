# usage: up.ps1 [-Locale zh-CN|en|''] [-Repo <checkout>] [-Dsh]
# Builds a checkout (this one, or -Repo) and starts its e2e build of Pointy
# on port 47397 with a scratch POINTY_HOME and an automation socket. With
# -Dsh, also starts the mock model on 47398 and DSH web on 3093 with the
# packed plugin. Prints the run directory; later scripts find it through
# $Runs\current.
param([string]$Locale = '', [string]$Repo = '', [switch]$Dsh)
$NoRun = $true
. (Join-Path $PSScriptRoot 'env.ps1')
if (-not $Repo) { $Repo = if ($env:VP_REPO) { $env:VP_REPO } else { $ToolRepo } }
$Repo = (Resolve-Path $Repo).Path

$ports = @($PointyPort)
if ($Dsh) { $ports += $MockPort, $DshPort }
foreach ($port in $ports) {
  if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
    throw "port $port is taken; another run may be up (down.ps1 it) or something else owns it"
  }
}
foreach ($tool in 'go', 'node') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not on PATH" }
}
$dshCmd = $null
if ($Dsh) {
  $wantDsh = if ($env:DSH) { $env:DSH } else { 'dsh.cmd' }
  $resolvedDsh = Get-Command $wantDsh -ErrorAction SilentlyContinue
  if (-not $resolvedDsh) { throw "$wantDsh is not on PATH (or set `$env:DSH)" }
  $dshCmd = $resolvedDsh.Source
  if ($dshCmd -like '*.ps1' -and (Test-Path ([IO.Path]::ChangeExtension($dshCmd, '.cmd')))) {
    $dshCmd = [IO.Path]::ChangeExtension($dshCmd, '.cmd')
  }
  if (-not (Get-Command 'pnpm' -ErrorAction SilentlyContinue)) { throw 'pnpm is not on PATH' }
}

New-Item -ItemType Directory -Force $Runs | Out-Null
# Keeps the evidence of the last VP_KEEP_RUNS (default 2) runs besides this one.
# Older run directories go, unless a process one of them recorded still lives.
$keepRuns = if ($env:VP_KEEP_RUNS) { [int]$env:VP_KEEP_RUNS } else { 2 }
Get-ChildItem $Runs -Directory | Sort-Object Name -Descending | Select-Object -Skip $keepRuns | Where-Object {
  -not (Get-ChildItem (Join-Path $_.FullName 'pids') -File -ErrorAction SilentlyContinue |
      Where-Object { Get-Process -Id ([int](Get-Content -Raw $_.FullName).Trim()) -ErrorAction SilentlyContinue })
} | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $Runs $stamp
if (Test-Path $runDir) { $runDir = Join-Path $Runs "$stamp-$(Get-Date -Format 'fff')" }
$env:VP_RUN = $runDir
New-Item -ItemType Directory -Force $env:VP_RUN | Out-Null
if ($Dsh) { Set-Content -LiteralPath (Join-Path $env:VP_RUN 'dsh') -Value '' -NoNewline }
$NoRun = $false
. (Join-Path $PSScriptRoot 'env.ps1')
New-Item -ItemType Directory -Force $Bin, (Join-Path $VP_RUN 'pids'), $PointyHome | Out-Null
if ($Dsh) {
  New-Item -ItemType Directory -Force (Join-Path $DshHome 'storages'), (Join-Path $VP_RUN 'ws') | Out-Null
}
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

# Runs $body with USERPROFILE/HOME/DSH_HOME pointed at this run's scratch dirs,
# then restores the caller's environment so nothing leaks past DSH setup.
function Invoke-WithDshEnv([hashtable]$extra, [scriptblock]$body) {
  $vars = @{
    USERPROFILE = $HomeDir
    HOME        = $HomeDir
    DSH_HOME    = $DshHome
    POINTY_PORT = "$PointyPort"
  }
  foreach ($k in $extra.Keys) { $vars[$k] = $extra[$k] }
  $saved = @{}
  foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
  try {
    foreach ($k in $vars.Keys) { [Environment]::SetEnvironmentVariable($k, $vars[$k]) }
    & $body
  } finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
  }
}

# Start-Logged runs a command through cmd.exe with shell redirection so the
# child does not inherit this script's stdout/stderr handles.
function Start-Logged([string]$cmdLine, [string]$logFile) {
  $inner = "$cmdLine > `"$logFile`" 2>&1"
  Start-Process cmd.exe -PassThru -WindowStyle Hidden -ArgumentList '/d', '/c', "`"$inner`""
}

$mockProc = $null
if ($Dsh) {
  $packLog = Join-Path $VP_RUN 'pack.log'
  Push-Location $Repo
  try {
    & npm.cmd pack ./plugin --pack-destination $VP_RUN *> $packLog
    if ($LASTEXITCODE -ne 0) { Die "npm pack failed, see $packLog" }
  } finally { Pop-Location }
  $tgz = Get-ChildItem -LiteralPath $VP_RUN -Filter '*.tgz' | Select-Object -First 1
  if (-not $tgz) { Die "npm pack wrote no .tgz in $VP_RUN, see $packLog" }

  $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.000Z')
  $wsId = '11111111-1111-4111-8111-111111111111'
  [ordered]@{
    unit   = [ordered]@{ name = 'workspace'; version = 2 }
    global = [ordered]@{ initialized = $true; workspaceIds = @($wsId); archivedSessionIds = @(); pinnedSessionIds = @() }
    tables = [ordered]@{
      workspaces = [ordered]@{
        $wsId = [ordered]@{ path = (Join-Path $VP_RUN 'ws'); title = 'verify-pointy'; sessionIds = @(); createdAt = $now; updatedAt = $now }
      }
    }
  } | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath (Join-Path $DshHome 'storages\workspace.json') -Encoding utf8

  $pluginLog = Join-Path $VP_RUN 'plugin-add.log'
  Invoke-WithDshEnv @{} {
    & $dshCmd plugin --profile web add "file:$($tgz.FullName)" *> $pluginLog
    if ($LASTEXITCODE -ne 0) { Die "dsh plugin add failed, see $pluginLog" }
  }

  $webProfile = Join-Path $DshHome 'profiles\web'
  New-Item -ItemType Directory -Force $webProfile | Out-Null
  $patch = @(
    '- id: agent-default-model'
    '  name: "@deepseek-ai/dsh-agent-default-model"'
    '  config:'
    '    provider: deepseek-official'
    '    model: deepseek-v4-flash'
  ) -join "`n"
  Set-Content -LiteralPath (Join-Path $webProfile 'cordis.patch.yml') -Value "$patch`n" -NoNewline -Encoding utf8

  $mockJsonl = Join-Path $EV 'mock.jsonl'
  Set-Content -LiteralPath $mockJsonl -Value '' -NoNewline -Encoding utf8
  $mockScript = Join-Path $Repo 'tools\mock-llm.ts'
  if (-not (Test-Path $mockScript)) { $mockScript = Join-Path $ToolRepo 'tools\mock-llm.ts' }
  $nodeExe = (Get-Command node).Source
  $mockProc = Start-Logged "`"$nodeExe`" `"$mockScript`" $MockPort `"$mockJsonl`"" (Join-Path $VP_RUN 'mock.log')
  Set-Content -LiteralPath (Join-Path $VP_RUN 'pids\mock') -Value $mockProc.Id
  Wait-Until 15 "the mock model on $MockPort" {
    $tree = @(Get-Tree $mockProc.Id)
    [bool]((Get-NetTCPConnection -LocalPort $MockPort -State Listen -ErrorAction SilentlyContinue).OwningProcess | Where-Object { $tree -contains $_ })
  }
}

# Pointy first: the plugin starts the Pointy.exe it carries when nothing listens.
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

if ($Dsh) {
  $dshProc = Invoke-WithDshEnv @{
    DEEPSEEK_BASE_URL = "http://127.0.0.1:$MockPort/anthropic"
    DEEPSEEK_API_KEY  = 'sk-mock-0000000000000000'
  } {
    Start-Logged "`"$dshCmd`" web --port $DshPort --no-open" (Join-Path $VP_RUN 'dsh.log')
  }
  Set-Content -LiteralPath (Join-Path $VP_RUN 'pids\dsh') -Value $dshProc.Id
  $errLog = Join-Path $PointyHome 'error.log'
  Wait-Until 120 'the plugin to connect' {
    (Test-Path $errLog) -and ((Get-Content -Raw -LiteralPath $errLog) -match 'dsh-ui')
  }
  Log "up: pointy=$($p.Id) dsh=$($dshProc.Id) mock=$($mockProc.Id) locale=$(if ($Locale) { $Locale } else { 'system' })"
} else {
  Log "up: pointy=$($p.Id) locale=$(if ($Locale) { $Locale } else { 'system' })"
}
"VP_RUN=$VP_RUN"

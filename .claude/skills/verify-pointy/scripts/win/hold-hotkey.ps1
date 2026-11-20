# usage: hold-hotkey.ps1 <mods> <vk> <ready file> [seconds]   registers a
# global shortcut for another process, as an app that already took it does,
# writes "held" to the ready file and holds it.
# mods are RegisterHotKey's MOD_* bits (1 Alt, 2 Ctrl, 4 Shift, 8 Win).
param([Parameter(Mandatory)][uint32]$Mods, [Parameter(Mandatory)][uint32]$Vk, [Parameter(Mandatory)][string]$Ready, [int]$Seconds = 300)
Add-Type -Namespace VerifyPointy -Name Hold -MemberDefinition '[DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);'
if (-not [VerifyPointy.Hold]::RegisterHotKey([IntPtr]::Zero, 1, $Mods, $Vk)) { Write-Error 'RegisterHotKey failed'; exit 1 }
Set-Content -LiteralPath $Ready -Value 'held'
Start-Sleep -Seconds $Seconds

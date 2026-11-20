# The fixture window fixture.ps1 starts: a text box holding -Text's lines.
param([Parameter(Mandatory)][string]$Text)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form -Property @{
  Text = 'verify-pointy fixture'; StartPosition = 'Manual'
  Location = New-Object System.Drawing.Point 120, 120; Size = New-Object System.Drawing.Size 820, 420
}
$box = New-Object System.Windows.Forms.TextBox -Property @{
  Multiline = $true; ReadOnly = $true; Dock = 'Fill'; WordWrap = $true; ScrollBars = 'Vertical'
  Font = New-Object System.Drawing.Font 'Segoe UI', 14
  Text = (Get-Content -Raw -LiteralPath $Text) -replace "`r?`n", "`r`n"
}
$form.Controls.Add($box)
Add-Type -Namespace VerifyPointy -Name Show -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);'
# Started hidden (no console), the process's first ShowWindow takes the
# hidden state from its start; showing again makes the form visible.
$form.Add_Shown({ [VerifyPointy.Show]::ShowWindow($form.Handle, 5) | Out-Null; $form.Activate(); $box.SelectionLength = 0 })
[System.Windows.Forms.Application]::Run($form)

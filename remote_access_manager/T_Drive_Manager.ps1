$ErrorActionPreference = "Continue"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Root "scripts\RemoteAccessConfig.ps1")

$MountScript = Join-Path $Root "mount_T_now.ps1"
$UnmountScript = Join-Path $Root "unmount_T.ps1"
$OpenVncScript = Join-Path $Root "open_vnc_viewer.ps1"
$Config = Get-RemoteAccessConfig

function Test-Port {
    param([int] $Port)
    $client = New-Object Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(800, $false)) { return $false }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function New-TextBox {
    param([int] $X, [int] $Y, [int] $W, [string] $Text = "", [switch] $Password)
    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point($X, $Y)
    $box.Size = New-Object System.Drawing.Size($W, 23)
    $box.Text = $Text
    if ($Password) { $box.UseSystemPasswordChar = $true }
    $box.AutoCompleteMode = "SuggestAppend"
    $box.AutoCompleteSource = "CustomSource"
    return $box
}

function Add-PasswordToggle {
    param(
        [System.Windows.Forms.TextBox] $Box,
        [int] $X,
        [int] $Y
    )
    $button = New-Object System.Windows.Forms.Button
    $button.Text = "Show"
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size(58, 23)
    $button.Add_Click({
        $Box.UseSystemPasswordChar = -not $Box.UseSystemPasswordChar
        $button.Text = if ($Box.UseSystemPasswordChar) { "Show" } else { "Hide" }
    })
    $form.Controls.Add($button)
}

function Add-Label {
    param([string] $Text, [int] $X, [int] $Y)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $form.Controls.Add($label)
}

function Add-History {
    param([System.Windows.Forms.TextBox] $Box, [string[]] $Values)
    $source = New-Object System.Windows.Forms.AutoCompleteStringCollection
    foreach ($value in $Values) {
        if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$source.Add($value) }
    }
    $Box.AutoCompleteCustomSource = $source
}

function Run-HiddenPowerShell {
    param(
        [string] $ScriptPath,
        [string[]] $ExtraArgs = @(),
        [hashtable] $Environment = @{}
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $quotedScript = '"' + $ScriptPath + '"'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $quotedScript " + ($ExtraArgs -join " ")
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    foreach ($key in $Environment.Keys) {
        $psi.EnvironmentVariables[$key] = [string]$Environment[$key]
    }
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    return $p.ExitCode
}

function Update-ConfigFromForm {
    $Config.ToolName = $txtToolName.Text.Trim()
    $Config.JumpHost = ($txtJumpHost.Text.Trim() -replace ',', '.')
    $Config.JumpUser = $txtJumpUser.Text.Trim()
    $Config.TargetHost = ($txtTargetHost.Text.Trim() -replace ',', '.')
    $Config.TargetUser = $txtTargetUser.Text.Trim()
    $Config.TargetPath = $txtTargetPath.Text.Trim()
    $Config.DriveLetter = $txtDrive.Text.Trim()
    $Config.MountCheckPath = $txtCheckPath.Text.Trim()
    $Config.IdentityFile = $txtIdentity.Text.Trim()
}

function Get-RunEnvironment {
    $envMap = @{}
    if ($txtJumpPassword.Text) { $envMap["REMOTE_ACCESS_JUMP_PASSWORD"] = $txtJumpPassword.Text }
    if ($txtTargetPassword.Text) { $envMap["REMOTE_ACCESS_TARGET_PASSWORD"] = $txtTargetPassword.Text }
    if ($txtVncPassword.Text) { $envMap["REMOTE_ACCESS_VNC_PASSWORD"] = $txtVncPassword.Text }
    return $envMap
}

function Get-StatusText {
    Update-ConfigFromForm
    $tMounted = Test-RemoteAccessMount -Config $Config
    $ssh = Test-Port ([int]$Config.LocalSshPort)
    $vnc = Test-Port ([int]$Config.LocalVncPort)
    $lines = @()
    $lines += "$($Config.DriveLetter) drive: " + ($(if ($tMounted) { "mounted" } else { "not mounted" }))
    $lines += "SSH tunnel $($Config.LocalSshPort): " + ($(if ($ssh) { "ready" } else { "not ready" }))
    $lines += "VNC tunnel $($Config.LocalVncPort): " + ($(if ($vnc) { "ready" } else { "not ready" }))
    $lines += ""
    $lines += "VNC address: 127.0.0.1::$($Config.LocalVncPort)"
    return ($lines -join [Environment]::NewLine)
}

function Refresh-Status {
    $statusBox.Text = Get-StatusText
}

$form = New-Object System.Windows.Forms.Form
$form.Text = $Config.ToolName
$form.Size = New-Object System.Drawing.Size(560, 520)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = $Config.ToolName
$title.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(18, 16)
$form.Controls.Add($title)

Add-Label "Tool name" 20 55
$txtToolName = New-TextBox 120 52 390 $Config.ToolName
$form.Controls.Add($txtToolName)

Add-Label "Jump host" 20 88
$txtJumpHost = New-TextBox 120 85 160 $Config.JumpHost
Add-History $txtJumpHost @($Config.JumpHost, "jump.example.internal")
$form.Controls.Add($txtJumpHost)

Add-Label "Jump user" 300 88
$txtJumpUser = New-TextBox 380 85 130 $Config.JumpUser
Add-History $txtJumpUser @($Config.JumpUser, "your-jump-user")
$form.Controls.Add($txtJumpUser)

Add-Label "Jump password" 20 121
$txtJumpPassword = New-TextBox 120 118 95 "" -Password
$form.Controls.Add($txtJumpPassword)
Add-PasswordToggle $txtJumpPassword 222 118

Add-Label "Target host" 20 157
$txtTargetHost = New-TextBox 120 154 160 $Config.TargetHost
Add-History $txtTargetHost @($Config.TargetHost, "target.example.internal")
$form.Controls.Add($txtTargetHost)

Add-Label "Target user" 300 157
$txtTargetUser = New-TextBox 380 154 130 $Config.TargetUser
Add-History $txtTargetUser @($Config.TargetUser, "your-target-user")
$form.Controls.Add($txtTargetUser)

Add-Label "Target password" 20 190
$txtTargetPassword = New-TextBox 120 187 95 "" -Password
$form.Controls.Add($txtTargetPassword)
Add-PasswordToggle $txtTargetPassword 222 187

Add-Label "Remote path" 20 223
$txtTargetPath = New-TextBox 120 220 260 $Config.TargetPath
Add-History $txtTargetPath @($Config.TargetPath, "/home/your-target-user")
$form.Controls.Add($txtTargetPath)

Add-Label "Drive" 400 223
$txtDrive = New-TextBox 450 220 60 $Config.DriveLetter
Add-History $txtDrive @($Config.DriveLetter, "T:", "S:", "R:")
$form.Controls.Add($txtDrive)

Add-Label "Check path" 20 256
$txtCheckPath = New-TextBox 120 253 160 $Config.MountCheckPath
Add-History $txtCheckPath @($Config.MountCheckPath, "workspace")
$form.Controls.Add($txtCheckPath)

Add-Label "SSH key" 300 256
$txtIdentity = New-TextBox 380 253 130 $Config.IdentityFile
$form.Controls.Add($txtIdentity)

Add-Label "VNC password" 20 289
$txtVncPassword = New-TextBox 120 286 95 "" -Password
$form.Controls.Add($txtVncPassword)
Add-PasswordToggle $txtVncPassword 222 286

$statusBox = New-Object System.Windows.Forms.TextBox
$statusBox.Multiline = $true
$statusBox.ReadOnly = $true
$statusBox.ScrollBars = "Vertical"
$statusBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$statusBox.Location = New-Object System.Drawing.Point(20, 325)
$statusBox.Size = New-Object System.Drawing.Size(490, 78)
$form.Controls.Add($statusBox)

$btnMount = New-Object System.Windows.Forms.Button
$btnMount.Text = "Connect"
$btnMount.Location = New-Object System.Drawing.Point(20, 420)
$btnMount.Size = New-Object System.Drawing.Size(95, 34)
$btnMount.Add_Click({
    Update-ConfigFromForm
    Save-RemoteAccessConfig -Config $Config
    $statusBox.Text = "Mounting $($Config.DriveLetter). Please wait..."
    $form.Refresh()
    $code = Run-HiddenPowerShell -ScriptPath $MountScript -Environment (Get-RunEnvironment)
    Refresh-Status
    if ($code -ne 0) {
        [System.Windows.Forms.MessageBox]::Show("$($Config.DriveLetter) mount failed. Check logs folder.", "Mount", "OK", "Warning") | Out-Null
    }
})
$form.Controls.Add($btnMount)

$btnUnmount = New-Object System.Windows.Forms.Button
$btnUnmount.Text = "Disconnect"
$btnUnmount.Location = New-Object System.Drawing.Point(125, 420)
$btnUnmount.Size = New-Object System.Drawing.Size(95, 34)
$btnUnmount.Add_Click({
    Update-ConfigFromForm
    Save-RemoteAccessConfig -Config $Config
    $statusBox.Text = "Unmounting $($Config.DriveLetter). Please wait..."
    $form.Refresh()
    $code = Run-HiddenPowerShell -ScriptPath $UnmountScript
    Refresh-Status
    if ($code -ne 0) {
        [System.Windows.Forms.MessageBox]::Show("$($Config.DriveLetter) unmount may have failed.", "Unmount", "OK", "Warning") | Out-Null
    }
})
$form.Controls.Add($btnUnmount)

$btnOpenDrive = New-Object System.Windows.Forms.Button
$btnOpenDrive.Text = "Open Drive"
$btnOpenDrive.Location = New-Object System.Drawing.Point(230, 420)
$btnOpenDrive.Size = New-Object System.Drawing.Size(95, 34)
$btnOpenDrive.Add_Click({
    Update-ConfigFromForm
    if (Test-RemoteAccessMount -Config $Config) {
        Start-Process "explorer.exe" (Get-RemoteAccessDriveRoot -Config $Config)
    } else {
        [System.Windows.Forms.MessageBox]::Show("$($Config.DriveLetter) is not mounted.", "Open Drive", "OK", "Information") | Out-Null
    }
})
$form.Controls.Add($btnOpenDrive)

$btnVnc = New-Object System.Windows.Forms.Button
$btnVnc.Text = "Open VNC"
$btnVnc.Location = New-Object System.Drawing.Point(335, 420)
$btnVnc.Size = New-Object System.Drawing.Size(80, 34)
$btnVnc.Add_Click({
    Update-ConfigFromForm
    Save-RemoteAccessConfig -Config $Config
    Run-HiddenPowerShell -ScriptPath $OpenVncScript -Environment (Get-RunEnvironment) | Out-Null
    Refresh-Status
})
$form.Controls.Add($btnVnc)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh"
$btnRefresh.Location = New-Object System.Drawing.Point(425, 420)
$btnRefresh.Size = New-Object System.Drawing.Size(85, 34)
$btnRefresh.Add_Click({ Refresh-Status })
$form.Controls.Add($btnRefresh)

$form.Add_Shown({ Refresh-Status })
[void]$form.ShowDialog()

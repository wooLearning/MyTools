$ErrorActionPreference = "Continue"

$env:PSExecutionPolicyPreference = "Bypass"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type -ReferencedAssemblies "System.Windows.Forms", "System.Drawing" -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class RemoteAccessTrayForm : Form {
    private const int WM_CLOSE = 0x0010;
    private const int WM_SYSCOMMAND = 0x0112;
    private const int SC_CLOSE = 0xF060;

    public bool AllowExit { get; set; }

    protected override void WndProc(ref Message m) {
        if (!AllowExit) {
            if (m.Msg == WM_CLOSE) {
                this.Hide();
                return;
            }
            if (m.Msg == WM_SYSCOMMAND && ((m.WParam.ToInt32() & 0xFFF0) == SC_CLOSE)) {
                this.Hide();
                return;
            }
        }
        base.WndProc(ref m);
    }

    protected override void OnFormClosing(FormClosingEventArgs e) {
        if (!AllowExit) {
            e.Cancel = true;
            this.Hide();
            return;
        }
        base.OnFormClosing(e);
    }

    protected override void OnClosing(CancelEventArgs e) {
        if (!AllowExit) {
            e.Cancel = true;
            this.Hide();
            return;
        }
        base.OnClosing(e);
    }
}

public static class RemoteAccessNativeWindow {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
"@

$currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
if ($currentProcess.ProcessName -ieq "RemoteAccessManager") {
    $currentPath = $currentProcess.MainModule.FileName
    $otherManagers = @(
        Get-CimInstance Win32_Process |
            Where-Object {
                $_.ProcessId -ne $currentProcess.Id -and
                $_.Name -ieq "RemoteAccessManager.exe" -and
                $_.ExecutablePath -eq $currentPath
            }
    )
    if ($otherManagers.Count -gt 0) {
        $existingWindow = [RemoteAccessNativeWindow]::FindWindow($null, "Remote Access Manager")
        if ($existingWindow -ne [IntPtr]::Zero) {
            [void][RemoteAccessNativeWindow]::ShowWindow($existingWindow, 9)
            [void][RemoteAccessNativeWindow]::SetForegroundWindow($existingWindow)
        }
        return
    }
}

$createdNew = $false
$script:AppMutex = New-Object System.Threading.Mutex($true, "Local\RemoteAccessManager", [ref]$createdNew)
if (-not $createdNew) {
    $existingWindow = [RemoteAccessNativeWindow]::FindWindow($null, "Remote Access Manager")
    if ($existingWindow -ne [IntPtr]::Zero) {
        [void][RemoteAccessNativeWindow]::ShowWindow($existingWindow, 9)
        [void][RemoteAccessNativeWindow]::SetForegroundWindow($existingWindow)
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Remote Access Manager is already running. Check the tray icon.",
            "Remote Access Manager",
            "OK",
            "Information"
        ) | Out-Null
    }
    return
}

function Get-ToolRoot {
    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        [void]$candidates.Add($PSScriptRoot)
    }
    if (-not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
        [void]$candidates.Add((Split-Path -Parent $MyInvocation.MyCommand.Path))
    }
    if (-not [string]::IsNullOrWhiteSpace([System.AppDomain]::CurrentDomain.BaseDirectory)) {
        [void]$candidates.Add([System.AppDomain]::CurrentDomain.BaseDirectory)
    }

    $processPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if (-not [string]::IsNullOrWhiteSpace($processPath)) {
        [void]$candidates.Add((Split-Path -Parent $processPath))
    }
    [void]$candidates.Add((Get-Location).Path)

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (Test-Path -LiteralPath (Join-Path $candidate "scripts\RemoteAccessConfig.ps1")) {
            return $candidate
        }
    }

    throw "Could not find scripts\RemoteAccessConfig.ps1 next to this tool."
}

$Root = Get-ToolRoot
. (Join-Path $Root "scripts\RemoteAccessConfig.ps1")

$MountScript = Join-Path $Root "mount_T_now.ps1"
$UnmountScript = Join-Path $Root "unmount_T.ps1"
$OpenVncScript = Join-Path $Root "open_vnc_viewer.ps1"
$RestoreScript = Join-Path $Root "restore_now.ps1"
$Config = Get-RemoteAccessConfig

function Get-RemoteAccessSecretsPath {
    Join-Path $Root "config.secrets.json"
}

function Protect-RemoteAccessSecret {
    param([string] $Value)
    if ([string]::IsNullOrEmpty($Value)) { return "" }
    $secure = ConvertTo-SecureString -String $Value -AsPlainText -Force
    return (ConvertFrom-SecureString -SecureString $secure)
}

function Unprotect-RemoteAccessSecret {
    param([string] $Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    try {
        $secure = ConvertTo-SecureString -String $Value
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        } finally {
            if ($bstr -ne [IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
    } catch {
        return ""
    }
}

function Load-RemoteAccessSecrets {
    $defaults = [ordered]@{
        JumpPassword = ""
        TargetPassword = ""
        VncPassword = ""
    }
    $path = Get-RemoteAccessSecretsPath
    if (-not (Test-Path -LiteralPath $path)) { return [pscustomobject]$defaults }

    try {
        $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        foreach ($name in @("JumpPassword", "TargetPassword", "VncPassword")) {
            if ($data.PSObject.Properties.Name -contains $name) {
                $defaults[$name] = Unprotect-RemoteAccessSecret ([string]$data.$name)
            }
        }
    } catch {
        # Keep the manager usable if the local secrets file is missing or stale.
    }
    [pscustomobject]$defaults
}

function Save-RemoteAccessSecrets {
    param(
        [string] $JumpPassword,
        [string] $TargetPassword,
        [string] $VncPassword
    )

    $safe = [ordered]@{
        JumpPassword = Protect-RemoteAccessSecret $JumpPassword
        TargetPassword = Protect-RemoteAccessSecret $TargetPassword
        VncPassword = Protect-RemoteAccessSecret $VncPassword
    }
    $safe | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Get-RemoteAccessSecretsPath) -Encoding UTF8
}

$Secrets = Load-RemoteAccessSecrets

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
    $button.Tag = $Box
    $button.Add_Click({
        param($Sender, $EventArgs)
        $target = [System.Windows.Forms.TextBox]$Sender.Tag
        $target.UseSystemPasswordChar = -not $target.UseSystemPasswordChar
        $Sender.Text = if ($target.UseSystemPasswordChar) { "Show" } else { "Hide" }
        $target.Refresh()
    })
    $form.Controls.Add($button)
}

function Add-FileBrowseButton {
    param(
        [System.Windows.Forms.TextBox] $Box,
        [int] $X,
        [int] $Y
    )
    $button = New-Object System.Windows.Forms.Button
    $button.Text = "Browse"
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size(70, 23)
    $button.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = "Select SSH key file"
        $dialog.InitialDirectory = Join-Path $env:USERPROFILE ".ssh"
        $dialog.Filter = "SSH key files|id_*;*.pem;*.key|All files|*.*"
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $Box.Text = $dialog.FileName
        }
    })
    $form.Controls.Add($button)
}

function Add-ClearButton {
    param(
        [System.Windows.Forms.TextBox] $Box,
        [int] $X,
        [int] $Y
    )
    $button = New-Object System.Windows.Forms.Button
    $button.Text = "Clear"
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size(58, 23)
    $button.Add_Click({ $Box.Text = "" })
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
    $Config.JumpHost = ($txtJumpHost.Text.Trim() -replace ',', '.')
    $Config.JumpUser = $txtJumpUser.Text.Trim()
    $Config.TargetHost = ($txtTargetHost.Text.Trim() -replace ',', '.')
    $Config.TargetUser = $txtTargetUser.Text.Trim()
    $Config.TargetPath = $txtTargetPath.Text.Trim()
    $Config.DriveLetter = $txtDrive.Text.Trim()
    $Config.MountCheckPath = $txtCheckPath.Text.Trim()
    $Config.IdentityFile = $txtIdentity.Text.Trim()
    $txtJumpHost.Text = $Config.JumpHost
    $txtTargetHost.Text = $Config.TargetHost
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

function Get-ConnectionState {
    Update-ConfigFromForm
    $mounted = Test-RemoteAccessMount -Config $Config
    $ssh = Test-Port ([int]$Config.LocalSshPort)
    $vnc = Test-Port ([int]$Config.LocalVncPort)

    $state = if ($mounted -and $ssh -and $vnc) {
        "Connected"
    } elseif ($mounted -or $ssh -or $vnc) {
        "Partial"
    } else {
        "Disconnected"
    }

    [pscustomobject]@{
        State = $state
        Mounted = $mounted
        Ssh = $ssh
        Vnc = $vnc
    }
}

function New-StatusIcon {
    param([string] $State)

    $color = switch ($State) {
        "Connected" { [System.Drawing.Color]::FromArgb(32, 168, 90) }
        "Partial" { [System.Drawing.Color]::FromArgb(235, 166, 35) }
        default { [System.Drawing.Color]::FromArgb(210, 64, 52) }
    }

    $bitmap = New-Object System.Drawing.Bitmap 16, 16
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $backBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(34, 42, 54))
    $stateBrush = New-Object System.Drawing.SolidBrush($color)
    $whitePen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 1)
    $graphics.FillRectangle($backBrush, 1, 1, 14, 14)
    $graphics.DrawRectangle($whitePen, 1, 1, 14, 14)
    $graphics.FillEllipse($stateBrush, 8, 8, 7, 7)

    $handle = $bitmap.GetHicon()
    $icon = ([System.Drawing.Icon]::FromHandle($handle)).Clone()
    [void][RemoteAccessNativeWindow]::DestroyIcon($handle)
    $graphics.Dispose()
    $backBrush.Dispose()
    $stateBrush.Dispose()
    $whitePen.Dispose()
    $bitmap.Dispose()
    return $icon
}

function Update-TrayStatusIcon {
    if (-not $script:TrayIcon) { return }
    $state = Get-ConnectionState
    $oldIcon = $script:TrayIcon.Icon
    $script:TrayIcon.Icon = New-StatusIcon -State $state.State
    $script:TrayIcon.Text = "Remote Access Manager: $($state.State)"
    if ($oldIcon) { $oldIcon.Dispose() }
}

function Refresh-Status {
    $statusBox.Text = Get-StatusText
    Update-TrayStatusIcon
}

function Show-MainWindow {
    if (-not $form.Visible) {
        $form.Show()
    }
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    }
    $form.Activate()
}

$script:AllowManagerExit = $false

$form = New-Object RemoteAccessTrayForm
$form.Text = $Config.ToolName
$form.Size = New-Object System.Drawing.Size(560, 485)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$script:TrayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIconPath = Join-Path $Root "remote_access_manager.ico"
if (Test-Path -LiteralPath $trayIconPath) {
    $script:TrayIcon.Icon = New-Object System.Drawing.Icon($trayIconPath)
} else {
    $script:TrayIcon.Icon = [System.Drawing.SystemIcons]::Application
}
$script:TrayIcon.Text = "Remote Access Manager"
$script:TrayIcon.Visible = $true
$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$trayShow = New-Object System.Windows.Forms.ToolStripMenuItem "Show"
$trayRefresh = New-Object System.Windows.Forms.ToolStripMenuItem "Refresh"
$trayExit = New-Object System.Windows.Forms.ToolStripMenuItem "Exit Manager"
$trayShow.Add_Click({ Show-MainWindow })
$trayRefresh.Add_Click({ Refresh-Status })
$trayExit.Add_Click({
    $script:AllowManagerExit = $true
    $form.AllowExit = $true
    $form.Close()
})
[void]$trayMenu.Items.Add($trayShow)
[void]$trayMenu.Items.Add($trayRefresh)
[void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$trayMenu.Items.Add($trayExit)
$script:TrayIcon.ContextMenuStrip = $trayMenu
$script:TrayIcon.Add_DoubleClick({ Show-MainWindow })

$script:TrayStatusTimer = New-Object System.Windows.Forms.Timer
$script:TrayStatusTimer.Interval = 10000
$script:TrayStatusTimer.Add_Tick({ Update-TrayStatusIcon })
$script:TrayStatusTimer.Start()

$title = New-Object System.Windows.Forms.Label
$title.Text = $Config.ToolName
$title.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(18, 16)
$form.Controls.Add($title)

Add-Label "Jump host" 20 55
$txtJumpHost = New-TextBox 120 52 160 $Config.JumpHost
Add-History $txtJumpHost @($Config.JumpHost, "jump.example.internal")
$form.Controls.Add($txtJumpHost)

Add-Label "Jump user" 300 55
$txtJumpUser = New-TextBox 380 52 130 $Config.JumpUser
Add-History $txtJumpUser @($Config.JumpUser, "your-jump-user")
$form.Controls.Add($txtJumpUser)

Add-Label "Jump password" 20 88
$txtJumpPassword = New-TextBox 120 85 95 $Secrets.JumpPassword -Password
$form.Controls.Add($txtJumpPassword)
Add-PasswordToggle $txtJumpPassword 222 85

Add-Label "Target host" 20 124
$txtTargetHost = New-TextBox 120 121 160 $Config.TargetHost
Add-History $txtTargetHost @($Config.TargetHost, "target.example.internal")
$form.Controls.Add($txtTargetHost)

Add-Label "Target user" 300 124
$txtTargetUser = New-TextBox 380 121 130 $Config.TargetUser
Add-History $txtTargetUser @($Config.TargetUser, "your-target-user")
$form.Controls.Add($txtTargetUser)

Add-Label "Target password" 20 157
$txtTargetPassword = New-TextBox 120 154 95 $Secrets.TargetPassword -Password
$form.Controls.Add($txtTargetPassword)
Add-PasswordToggle $txtTargetPassword 222 154

Add-Label "Remote path" 20 190
$txtTargetPath = New-TextBox 120 187 260 $Config.TargetPath
Add-History $txtTargetPath @($Config.TargetPath, "/home/your-target-user")
$form.Controls.Add($txtTargetPath)

Add-Label "Drive" 400 190
$txtDrive = New-TextBox 450 187 60 $Config.DriveLetter
Add-History $txtDrive @($Config.DriveLetter, "T:", "S:", "R:")
$form.Controls.Add($txtDrive)

Add-Label "Check path" 20 223
$txtCheckPath = New-TextBox 120 220 160 $Config.MountCheckPath
Add-History $txtCheckPath @($Config.MountCheckPath, "workspace")
$form.Controls.Add($txtCheckPath)

Add-Label "SSH key" 300 223
$txtIdentity = New-TextBox 380 220 130 $Config.IdentityFile
$form.Controls.Add($txtIdentity)
Add-FileBrowseButton $txtIdentity 380 248
Add-ClearButton $txtIdentity 452 248

Add-Label "VNC password" 20 256
$txtVncPassword = New-TextBox 120 253 95 $Secrets.VncPassword -Password
$form.Controls.Add($txtVncPassword)
Add-PasswordToggle $txtVncPassword 222 253

$statusBox = New-Object System.Windows.Forms.TextBox
$statusBox.Multiline = $true
$statusBox.ReadOnly = $true
$statusBox.ScrollBars = "Vertical"
$statusBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$statusBox.Location = New-Object System.Drawing.Point(20, 292)
$statusBox.Size = New-Object System.Drawing.Size(490, 78)
$form.Controls.Add($statusBox)

$btnMount = New-Object System.Windows.Forms.Button
$btnMount.Text = "Connect"
$btnMount.Location = New-Object System.Drawing.Point(20, 387)
$btnMount.Size = New-Object System.Drawing.Size(95, 34)
$btnMount.Add_Click({
    Update-ConfigFromForm
    Save-RemoteAccessConfig -Config $Config
    Save-RemoteAccessSecrets -JumpPassword $txtJumpPassword.Text -TargetPassword $txtTargetPassword.Text -VncPassword $txtVncPassword.Text
    $statusBox.Text = "Connecting drive and VNC. Please wait..."
    $form.Refresh()
    $envMap = Get-RunEnvironment
    $envMap["REMOTE_ACCESS_AUTO_MOUNT_T"] = "1"
    $code = Run-HiddenPowerShell -ScriptPath $RestoreScript -Environment $envMap
    Refresh-Status
    if ($code -ne 0) {
        [System.Windows.Forms.MessageBox]::Show("Connect failed. Check logs folder.", "Connect", "OK", "Warning") | Out-Null
    }
})
$form.Controls.Add($btnMount)

$btnUnmount = New-Object System.Windows.Forms.Button
$btnUnmount.Text = "Disconnect"
$btnUnmount.Location = New-Object System.Drawing.Point(125, 387)
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
$btnOpenDrive.Location = New-Object System.Drawing.Point(230, 387)
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
$btnVnc.Location = New-Object System.Drawing.Point(335, 387)
$btnVnc.Size = New-Object System.Drawing.Size(80, 34)
$btnVnc.Add_Click({
    Update-ConfigFromForm
    Save-RemoteAccessConfig -Config $Config
    Save-RemoteAccessSecrets -JumpPassword $txtJumpPassword.Text -TargetPassword $txtTargetPassword.Text -VncPassword $txtVncPassword.Text
    Run-HiddenPowerShell -ScriptPath $OpenVncScript -Environment (Get-RunEnvironment) | Out-Null
    Refresh-Status
})
$form.Controls.Add($btnVnc)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh"
$btnRefresh.Location = New-Object System.Drawing.Point(425, 387)
$btnRefresh.Size = New-Object System.Drawing.Size(85, 34)
$btnRefresh.Add_Click({ Refresh-Status })
$form.Controls.Add($btnRefresh)

$form.Add_Shown({
    Refresh-Status
    $script:TrayIcon.Visible = $true
})
$form.Add_Resize({
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        $form.Hide()
        $script:TrayIcon.ShowBalloonTip(
            1500,
            "Remote Access Manager",
            "Manager is in the tray. Existing SSH/VNC sessions are unchanged.",
            [System.Windows.Forms.ToolTipIcon]::Info
        )
    }
})
$form.Add_FormClosing({
    param($Sender, $EventArgs)
    if (-not $script:AllowManagerExit) {
        $EventArgs.Cancel = $true
        $form.Hide()
        $script:TrayIcon.ShowBalloonTip(
            1500,
            "Remote Access Manager",
            "Manager is still running in the tray. Existing SSH/VNC sessions are unchanged.",
            [System.Windows.Forms.ToolTipIcon]::Info
        )
    }
})
$form.Add_FormClosed({
    if ($script:TrayStatusTimer) {
        $script:TrayStatusTimer.Stop()
        $script:TrayStatusTimer.Dispose()
    }
    if ($script:TrayIcon) {
        $script:TrayIcon.Visible = $false
        $script:TrayIcon.Dispose()
    }
    if ($script:AppMutex) {
        try { $script:AppMutex.ReleaseMutex() } catch {}
        $script:AppMutex.Dispose()
    }
})
[System.Windows.Forms.Application]::Run($form)

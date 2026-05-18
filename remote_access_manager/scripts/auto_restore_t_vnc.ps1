$ErrorActionPreference = "Continue"

$BaseDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "RemoteAccessConfig.ps1")
$Config = Get-RemoteAccessConfig

$LogDir = Join-Path $BaseDir "logs\auto_restore_logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("restore_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

function Log {
    param([string] $Message)
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Run {
    param(
        [string] $FilePath,
        [string[]] $ArgumentList,
        [int] $TimeoutSeconds = 20
    )

    $out = Join-Path $LogDir ("cmd_{0}_out.log" -f ([guid]::NewGuid().ToString("N")))
    $err = Join-Path $LogDir ("cmd_{0}_err.log" -f ([guid]::NewGuid().ToString("N")))
    $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        try { $p.Kill() } catch {}
        Log "TIMEOUT: $FilePath $($ArgumentList -join ' ')"
        return $false
    }
    if (Test-Path $out) { Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue | ForEach-Object { if ($_) { Log $_.TrimEnd() } } }
    if (Test-Path $err) { Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue | ForEach-Object { if ($_) { Log $_.TrimEnd() } } }
    return ($p.ExitCode -eq 0)
}

function Test-Port {
    param([int] $Port)
    $client = New-Object Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(1500, $false)) { return $false }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Ensure-SshConfig {
    $cfg = Join-Path $env:USERPROFILE ".ssh\config"
    $dir = Split-Path -Parent $cfg
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $text = if (Test-Path -LiteralPath $cfg) { Get-Content -LiteralPath $cfg -Raw } else { "" }
    $aliases = @([regex]::Escape($Config.JumpAlias), [regex]::Escape($Config.TargetAlias), "A-jump", "C-via-A") -join "|"
    $text = [regex]::Replace($text, "(?ms)^Host\s+(?:$aliases)\s*.*?(?=^Host\s|\z)", "")
    $block = @(
        "Host $($Config.JumpAlias)",
        "  HostName $($Config.JumpHost)",
        "  User $($Config.JumpUser)",
        "",
        "Host $($Config.TargetAlias)",
        "  HostName $($Config.TargetHost)",
        "  User $($Config.TargetUser)",
        "  ProxyJump $($Config.JumpAlias)"
    ) -join [Environment]::NewLine
    $out = $text.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block + [Environment]::NewLine
    Set-Content -LiteralPath $cfg -Value $out -NoNewline -Encoding ascii
    Log "SSH config ensured: $cfg"
}

function Ensure-Tunnel {
    if (Test-Port ([int]$Config.LocalSshPort)) {
        Log "SSH tunnel $($Config.LocalSshPort) already listening"
        return
    }
    Log "Starting SSH tunnel $($Config.LocalSshPort)"
    Invoke-WithRemoteAccessEnvironment -Config $Config -Script {
        Start-Process -FilePath $Config.SshExe `
            -ArgumentList @("-N", "-L", "127.0.0.1:$($Config.LocalSshPort):$($Config.TargetHost):$($Config.RemoteSshPort)", "-o", "ExitOnForwardFailure=yes", "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3", $Config.JumpAlias) `
            -WindowStyle Hidden
    }
    Start-Sleep -Seconds 5
    Log ("Tunnel $($Config.LocalSshPort) listening={0}" -f (Test-Port ([int]$Config.LocalSshPort)))
}

function Ensure-TDrive {
    if (Test-RemoteAccessMount -Config $Config) {
        Log "$($Config.DriveLetter) already mounted"
        return
    }

    Log "Mounting $($Config.DriveLetter)"
    & (Join-Path $BaseDir "mount_T_now.ps1") | Out-Null
    Log ("Drive mounted={0}" -f (Test-RemoteAccessMount -Config $Config))
}

function Ensure-RemoteVnc {
    $vncPass = [string]$Config.VncPassword
    $passLine = if ($vncPass) {
        "printf '%s\n' $(Escape-SingleQuotedShellString $vncPass) | vncpasswd -f > `"$HOME/.vnc/passwd`""
    } else {
        "test -s `"$HOME/.vnc/passwd`""
    }

    $script = @"
#!/usr/bin/env bash
set -e
export DISPLAY=:$($Config.VncDisplay)
mkdir -p "`$HOME/.vnc"
chmod 700 "`$HOME/.vnc"
$passLine
chmod 600 "`$HOME/.vnc/passwd"
if ! pgrep -u "`$USER" -f 'Xvnc :$($Config.VncDisplay)\b' >/dev/null 2>&1; then
  cat > "`$HOME/.vnc/xstartup" <<'EOS'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export SHELL=/bin/csh
if command -v mwm >/dev/null 2>&1; then
  mwm &
fi
sleep infinity
EOS
  chmod 755 "`$HOME/.vnc/xstartup"
  vncserver :$($Config.VncDisplay) -localhost -geometry "$($Config.VncGeometry)" -depth $($Config.VncDepth) -rfbauth "`$HOME/.vnc/passwd" || true
fi
if ! pgrep -u "`$USER" -x mwm >/dev/null 2>&1; then
  DISPLAY=:$($Config.VncDisplay) nohup /usr/bin/mwm > "`$HOME/.vnc/mwm-display$($Config.VncDisplay).log" 2>&1 &
fi
ss -ltn | grep -q ':$($Config.RemoteVncPort) '
"@
    $tmp = Join-Path $env:TEMP ("ensure_remote_vnc_{0}.sh" -f ([guid]::NewGuid().ToString("N")))
    Set-Content -LiteralPath $tmp -Value ($script -replace "`r`n", "`n") -Encoding ascii
    try {
        Invoke-WithRemoteAccessEnvironment -Config $Config -Script {
            Run $Config.ScpExe @("-P", [string]$Config.LocalSshPort, "-o", "BatchMode=no", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=NUL", $tmp, "$($Config.TargetUser)@127.0.0.1:/tmp/ensure_remote_vnc.sh") 20 | Out-Null
            Run $Config.SshExe @("-p", [string]$Config.LocalSshPort, "-o", "BatchMode=no", "-o", "ConnectTimeout=10", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=NUL", "$($Config.TargetUser)@127.0.0.1", "bash /tmp/ensure_remote_vnc.sh") 30 | Out-Null
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    Log "Remote VNC ensured"
}

function Ensure-VncTunnel {
    if (Test-Port ([int]$Config.LocalVncPort)) {
        Log "VNC tunnel $($Config.LocalVncPort) already listening"
        return
    }
    Log "Starting VNC tunnel $($Config.LocalVncPort)"
    Invoke-WithRemoteAccessEnvironment -Config $Config -Script {
        Start-Process -FilePath $Config.SshExe `
            -ArgumentList @("-N", "-L", "127.0.0.1:$($Config.LocalVncPort):127.0.0.1:$($Config.RemoteVncPort)", "-o", "ExitOnForwardFailure=yes", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=NUL", "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3", $Config.TargetAlias) `
            -WindowStyle Hidden
    }
    Start-Sleep -Seconds 5
    Log ("VNC tunnel $($Config.LocalVncPort) listening={0}" -f (Test-Port ([int]$Config.LocalVncPort)))
}

try {
    Log "=== auto restore start ==="
    Ensure-SshConfig
    Ensure-Tunnel
    if ($env:REMOTE_ACCESS_AUTO_MOUNT_T -eq "1") {
        Ensure-TDrive
    } else {
        Log "$($Config.DriveLetter) auto mount skipped. Run mount_T_now.ps1 when needed."
    }
    Ensure-RemoteVnc
    Ensure-VncTunnel
    Log "=== auto restore done ==="
} catch {
    Log "ERROR: $($_.Exception.Message)"
    Log $_.ScriptStackTrace
}

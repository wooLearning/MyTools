param(
    [switch] $OpenExplorer
)

$ErrorActionPreference = "Continue"

. (Join-Path $PSScriptRoot "scripts\RemoteAccessConfig.ps1")
$Config = Get-RemoteAccessConfig -PromptMissing

$Root = $PSScriptRoot
$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("mount_{0}_{1:yyyyMMdd_HHmmss}.log" -f (($Config.DriveLetter -replace '[:\\]', '').ToUpperInvariant()), (Get-Date))

function Log {
    param([string] $Message)
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $line
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

function Stop-DriveMountProcesses {
    $targetPattern = [regex]::Escape(("{0}@127.0.0.1:{1}" -f $Config.TargetUser, $Config.TargetPath))
    $drivePattern = "\s" + [regex]::Escape($Config.DriveLetter)
    Get-CimInstance Win32_Process |
        Where-Object {
            ($_.Name -eq "sshfs.exe" -and $_.CommandLine -match $targetPattern -and $_.CommandLine -match $drivePattern) -or
            ($_.Name -eq "ssh.exe" -and $_.CommandLine -match "SSHFS-Win\\bin\\ssh\.exe")
        } |
        ForEach-Object {
            Log "Stopping stale process PID=$($_.ProcessId) NAME=$($_.Name)"
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

function Open-DriveIfRequested {
    if ($OpenExplorer) {
        explorer.exe (Get-RemoteAccessDriveRoot -Config $Config)
    }
}

$driveRoot = Get-RemoteAccessDriveRoot -Config $Config
if (Test-RemoteAccessMount -Config $Config) {
    Log "$($Config.DriveLetter) already mounted."
    Open-DriveIfRequested
    exit 0
}

if (Test-Path $driveRoot) {
    Log "$($Config.DriveLetter) exists but check path is missing. Cleaning stale mount."
    Stop-DriveMountProcesses
    cmd /c "net use $($Config.DriveLetter) /delete /y" 2>$null | Out-Null
    Start-Sleep -Seconds 3
}

if (-not (Test-Port ([int]$Config.LocalSshPort))) {
    Log "Starting SSH tunnel 127.0.0.1:$($Config.LocalSshPort) -> target SSH through jump host."
    Invoke-WithRemoteAccessEnvironment -Config $Config -Script {
        Start-Process -FilePath $Config.SshExe `
            -ArgumentList @("-N", "-L", "127.0.0.1:$($Config.LocalSshPort):$($Config.TargetHost):$($Config.RemoteSshPort)", "-o", "ExitOnForwardFailure=yes", "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3", $Config.JumpAlias) `
            -WindowStyle Hidden
    }
    Start-Sleep -Seconds 5
}

if (-not (Test-Port ([int]$Config.LocalSshPort))) {
    Log "ERROR: SSH tunnel $($Config.LocalSshPort) is not listening."
    exit 1
}

if (-not (Test-Path -LiteralPath $Config.SshfsExe)) {
    Log "ERROR: Missing sshfs.exe: $($Config.SshfsExe)"
    exit 1
}

for ($attempt = 1; $attempt -le 2; $attempt++) {
    Log "Mounting $($Config.DriveLetter) to configured remote path. Attempt $attempt."
    Stop-DriveMountProcesses
    cmd /c "net use $($Config.DriveLetter) /delete /y" 2>$null | Out-Null
    Start-Sleep -Seconds 2

    $args = @(
        ("{0}@127.0.0.1:{1}" -f $Config.TargetUser, $Config.TargetPath),
        $Config.DriveLetter,
        "-p", [string]$Config.LocalSshPort
    )
    if (-not [string]::IsNullOrWhiteSpace([string]$Config.IdentityFile)) {
        $args += @("-o", ("IdentityFile={0}" -f (ConvertTo-CygwinPath $Config.IdentityFile)))
    }
    $batchMode = if ($Config.PSObject.Properties.Name -contains "TargetPassword" -and $Config.TargetPassword) { "no" } else { "yes" }
    $args += @(
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", ("BatchMode={0}" -f $batchMode),
        "-o", "idmap=user",
        "-o", "umask=000",
        "-o", ("volname={0}@{1}" -f $Config.TargetUser, $Config.TargetHost),
        "-o", "reconnect"
    )

    $stdoutLog = Join-Path $LogDir ("sshfs_mount_{0}_out.log" -f ([guid]::NewGuid().ToString("N")))
    $stderrLog = Join-Path $LogDir ("sshfs_mount_{0}_err.log" -f ([guid]::NewGuid().ToString("N")))
    $env:PATH = "C:\Program Files\SSHFS-Win\bin;$env:PATH"

    Invoke-WithRemoteAccessEnvironment -Config $Config -Script {
        $script:proc = Start-Process `
            -FilePath $Config.SshfsExe `
            -ArgumentList $args `
            -WorkingDirectory (Split-Path -Parent $Config.SshfsExe) `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdoutLog `
            -RedirectStandardError $stderrLog `
            -PassThru
    }

    Log "Started sshfs.exe PID=$($proc.Id) with hidden file redirection."

    for ($i = 1; $i -le 20; $i++) {
        Start-Sleep -Seconds 1
        if (Test-RemoteAccessMount -Config $Config) {
            Log "$($Config.DriveLetter) mounted successfully."
            Open-DriveIfRequested
            exit 0
        }
        if ($proc.HasExited) {
            Log "sshfs.exe exited early with code $($proc.ExitCode)."
            try {
                $stderr = if (Test-Path -LiteralPath $stderrLog) { Get-Content -LiteralPath $stderrLog -Raw -ErrorAction SilentlyContinue } else { "" }
                if ($stderr) { Log ("sshfs stderr: " + $stderr.Trim()) }
            } catch {}
            break
        }
    }

    Log "Attempt $attempt did not mount $($Config.DriveLetter)."
}

Log "ERROR: $($Config.DriveLetter) mount failed."
Stop-DriveMountProcesses
exit 1

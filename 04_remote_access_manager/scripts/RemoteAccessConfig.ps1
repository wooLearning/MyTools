$script:RemoteAccessBaseDir = Split-Path -Parent $PSScriptRoot

function Get-RemoteAccessDefaultConfig {
    @{
        ToolName = "Remote Access Manager"
        JumpAlias = "remote-jump"
        JumpHost = ""
        JumpUser = ""
        TargetAlias = "remote-target"
        TargetHost = ""
        TargetUser = ""
        TargetPath = ""
        DriveLetter = "T:"
        MountCheckPath = "workspace"
        IdentityFile = (Join-Path $env:USERPROFILE ".ssh\id_ed25519")
        SshExe = "C:\Windows\System32\OpenSSH\ssh.exe"
        ScpExe = "C:\Windows\System32\OpenSSH\scp.exe"
        SshfsExe = "C:\Program Files\SSHFS-Win\bin\sshfs.exe"
        LocalSshPort = 22220
        RemoteSshPort = 22
        LocalVncPort = 15917
        RemoteVncPort = 5917
        VncDisplay = 17
        VncViewer = "C:\Program Files\TigerVNC\vncviewer.exe"
        VncGeometry = "1600x1000"
        VncDepth = 24
        VncPassword = ""
    }
}

function Merge-RemoteAccessConfigFile {
    param(
        [System.Collections.IDictionary] $Config,
        [string] $Path
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $json = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if (-not $json.Trim()) { return }
    $data = $json | ConvertFrom-Json
    foreach ($prop in $data.PSObject.Properties) {
        if ($Config.Contains($prop.Name)) {
            $Config[$prop.Name] = $prop.Value
        }
    }
}

function Get-RemoteAccessConfigPath {
    Join-Path $script:RemoteAccessBaseDir "config.local.json"
}

function Get-RemoteAccessConfig {
    param([switch] $PromptMissing)

    $cfg = Get-RemoteAccessDefaultConfig
    Merge-RemoteAccessConfigFile -Config $cfg -Path (Join-Path $script:RemoteAccessBaseDir "config.example.json")
    Merge-RemoteAccessConfigFile -Config $cfg -Path (Get-RemoteAccessConfigPath)

    if ($env:REMOTE_ACCESS_JUMP_PASSWORD) { $cfg["JumpPassword"] = $env:REMOTE_ACCESS_JUMP_PASSWORD }
    if ($env:REMOTE_ACCESS_TARGET_PASSWORD) { $cfg["TargetPassword"] = $env:REMOTE_ACCESS_TARGET_PASSWORD }
    if ($env:REMOTE_ACCESS_VNC_PASSWORD) { $cfg["VncPassword"] = $env:REMOTE_ACCESS_VNC_PASSWORD }

    if ($PromptMissing) {
        foreach ($name in @("JumpHost", "JumpUser", "TargetHost", "TargetUser", "TargetPath", "DriveLetter")) {
            if ([string]::IsNullOrWhiteSpace([string]$cfg[$name])) {
                $cfg[$name] = Read-Host $name
            }
        }
    }

    [pscustomobject]$cfg
}

function Save-RemoteAccessConfig {
    param([pscustomobject] $Config)

    $path = Get-RemoteAccessConfigPath
    $safe = [ordered]@{}
    foreach ($name in @(
        "ToolName", "JumpAlias", "JumpHost", "JumpUser", "TargetAlias", "TargetHost", "TargetUser",
        "TargetPath", "DriveLetter", "MountCheckPath", "IdentityFile", "SshExe", "ScpExe", "SshfsExe",
        "LocalSshPort", "RemoteSshPort", "LocalVncPort", "RemoteVncPort", "VncDisplay",
        "VncViewer", "VncGeometry", "VncDepth"
    )) {
        $safe[$name] = $Config.$name
    }
    $safe["VncPassword"] = ""
    $safe | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-RemoteAccessDriveRoot {
    param([pscustomobject] $Config)
    $drive = [string]$Config.DriveLetter
    if ($drive -notmatch ':$') { $drive += ":" }
    $drive + "\"
}

function Test-RemoteAccessMount {
    param([pscustomobject] $Config)
    $root = Get-RemoteAccessDriveRoot -Config $Config
    if (-not (Test-Path $root)) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$Config.MountCheckPath)) { return $true }
    return (Test-Path (Join-Path $root ([string]$Config.MountCheckPath)))
}

function ConvertTo-CygwinPath {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    if ($Path -match '^([A-Za-z]):\\(.*)$') {
        return ("/cygdrive/{0}/{1}" -f $matches[1].ToLowerInvariant(), ($matches[2] -replace '\\', '/'))
    }
    $Path
}

function Set-RemoteAccessAskPassEnvironment {
    param(
        [pscustomobject] $Config,
        [hashtable] $Environment = @{}
    )
    $askPass = Join-Path $PSScriptRoot "ssh_askpass.cmd"
    $Environment["SSH_ASKPASS"] = $askPass
    $Environment["SSH_ASKPASS_REQUIRE"] = "force"
    $Environment["DISPLAY"] = "windows:0"
    $Environment["REMOTE_ACCESS_JUMP_USER"] = [string]$Config.JumpUser
    $Environment["REMOTE_ACCESS_JUMP_HOST"] = [string]$Config.JumpHost
    $Environment["REMOTE_ACCESS_TARGET_USER"] = [string]$Config.TargetUser
    $Environment["REMOTE_ACCESS_TARGET_HOST"] = [string]$Config.TargetHost
    if ($Config.PSObject.Properties.Name -contains "JumpPassword") {
        $Environment["REMOTE_ACCESS_JUMP_PASSWORD"] = [string]$Config.JumpPassword
    }
    if ($Config.PSObject.Properties.Name -contains "TargetPassword") {
        $Environment["REMOTE_ACCESS_TARGET_PASSWORD"] = [string]$Config.TargetPassword
    }
    $Environment
}

function Invoke-WithRemoteAccessEnvironment {
    param(
        [pscustomobject] $Config,
        [scriptblock] $Script
    )
    $envMap = Set-RemoteAccessAskPassEnvironment -Config $Config
    $old = @{}
    foreach ($key in $envMap.Keys) {
        $old[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
        [Environment]::SetEnvironmentVariable($key, [string]$envMap[$key], "Process")
    }
    try {
        & $Script
    } finally {
        foreach ($key in $envMap.Keys) {
            [Environment]::SetEnvironmentVariable($key, $old[$key], "Process")
        }
    }
}

function Escape-SingleQuotedShellString {
    param([string] $Value)
    "'" + ($Value -replace "'", "'\''") + "'"
}

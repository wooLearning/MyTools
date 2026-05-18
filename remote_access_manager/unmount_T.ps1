$ErrorActionPreference = "Continue"

. (Join-Path $PSScriptRoot "scripts\RemoteAccessConfig.ps1")
$Config = Get-RemoteAccessConfig

$targetPattern = [regex]::Escape(("{0}@127.0.0.1:{1}" -f $Config.TargetUser, $Config.TargetPath))
$drivePattern = "\s" + [regex]::Escape($Config.DriveLetter)

Get-CimInstance Win32_Process |
    Where-Object {
        ($_.Name -eq "sshfs.exe" -and $_.CommandLine -match $targetPattern -and $_.CommandLine -match $drivePattern) -or
        ($_.Name -eq "ssh.exe" -and $_.CommandLine -match "SSHFS-Win\\bin\\ssh\.exe")
    } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

cmd /c "net use $($Config.DriveLetter) /delete /y" 2>$null | Out-Null
Start-Sleep -Seconds 2

if (Test-Path (Get-RemoteAccessDriveRoot -Config $Config)) {
    Write-Host "$($Config.DriveLetter) still exists. It may be held by another process."
    exit 1
}

Write-Host "$($Config.DriveLetter) unmounted."

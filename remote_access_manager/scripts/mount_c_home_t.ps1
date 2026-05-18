$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $root 'mount_T_now.ps1') -OpenExplorer

Write-Host ''
Write-Host 'sshfs.exe exited. Press Enter to close this window.'
[void][Console]::ReadLine()

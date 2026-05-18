$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot "RemoteAccessConfig.ps1")
$Config = Get-RemoteAccessConfig -PromptMissing

Write-Host ''
Write-Host "Starting SSH tunnel: local -> jump -> target($($Config.TargetHost):$($Config.RemoteSshPort))"
Write-Host 'Keep this window open while the drive is mounted.'
Write-Host ''

Invoke-WithRemoteAccessEnvironment -Config $Config -Script {
  & $Config.SshExe `
    -N `
    -L "127.0.0.1:$($Config.LocalSshPort):$($Config.TargetHost):$($Config.RemoteSshPort)" `
    -o ExitOnForwardFailure=yes `
    $Config.JumpAlias
}

Write-Host ''
Write-Host 'Tunnel process exited. Press Enter to close this window.'
[void][Console]::ReadLine()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "scripts\RemoteAccessConfig.ps1")
$Config = Get-RemoteAccessConfig

if (-not (Test-Path -LiteralPath $Config.VncViewer)) {
    throw "VNC Viewer not found: $($Config.VncViewer)"
}

Start-Process -FilePath $Config.VncViewer -ArgumentList ("127.0.0.1::{0}" -f $Config.LocalVncPort)

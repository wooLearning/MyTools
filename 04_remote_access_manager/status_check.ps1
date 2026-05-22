$ErrorActionPreference = "Continue"

. (Join-Path $PSScriptRoot "scripts\RemoteAccessConfig.ps1")
$Config = Get-RemoteAccessConfig

"=== Drives ==="
fsutil fsinfo drives
""
"=== $($Config.DriveLetter) ==="
if (Test-RemoteAccessMount -Config $Config) {
    "$($Config.DriveLetter) mount OK"
} else {
    "$($Config.DriveLetter) mount MISSING"
}
""
"=== Local Tunnels ==="
Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort ([int]$Config.LocalSshPort),([int]$Config.LocalVncPort) -State Listen -ErrorAction SilentlyContinue |
    Select-Object LocalAddress,LocalPort,State,OwningProcess
""
"=== Startup Shortcut ==="
$startup = [Environment]::GetFolderPath("Startup")
$restoreShortcut = Join-Path $startup "Remote Access Restore.lnk"
if (Test-Path -LiteralPath $restoreShortcut) {
    $item = Get-Item -LiteralPath $restoreShortcut
    "Startup restore shortcut OK: $($item.FullName)"
} else {
    "Remote Access Restore startup shortcut MISSING"
}

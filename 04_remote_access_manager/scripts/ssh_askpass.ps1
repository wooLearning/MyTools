param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Prompt)

$text = ($Prompt -join " ")
$jumpUser = [regex]::Escape([string]$env:REMOTE_ACCESS_JUMP_USER)
$jumpHost = [regex]::Escape([string]$env:REMOTE_ACCESS_JUMP_HOST)
$targetUser = [regex]::Escape([string]$env:REMOTE_ACCESS_TARGET_USER)
$targetHost = [regex]::Escape([string]$env:REMOTE_ACCESS_TARGET_HOST)

if ($env:REMOTE_ACCESS_JUMP_PASSWORD -and (($jumpUser -and $text -match $jumpUser) -or ($jumpHost -and $text -match $jumpHost))) {
    [Console]::Out.Write($env:REMOTE_ACCESS_JUMP_PASSWORD)
    exit 0
}

if ($env:REMOTE_ACCESS_TARGET_PASSWORD -and (($targetUser -and $text -match $targetUser) -or ($targetHost -and $text -match $targetHost))) {
    [Console]::Out.Write($env:REMOTE_ACCESS_TARGET_PASSWORD)
    exit 0
}

if ($env:REMOTE_ACCESS_TARGET_PASSWORD) {
    [Console]::Out.Write($env:REMOTE_ACCESS_TARGET_PASSWORD)
    exit 0
}

if ($env:REMOTE_ACCESS_JUMP_PASSWORD) {
    [Console]::Out.Write($env:REMOTE_ACCESS_JUMP_PASSWORD)
}

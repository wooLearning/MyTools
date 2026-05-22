param(
    [string]$SessionPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Set-CodexPaths {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path $env:USERPROFILE ".codex"
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim('"'))
    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        $expanded = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $expanded))
    }

    $leaf = Split-Path -Leaf $expanded
    if ($leaf -ieq "sessions") {
        $script:SessionsRoot = $expanded
        $script:CodexHome = Split-Path -Parent $expanded
    } elseif (Test-Path -LiteralPath (Join-Path $expanded "sessions")) {
        $script:CodexHome = $expanded
        $script:SessionsRoot = Join-Path $expanded "sessions"
    } else {
        $script:SessionsRoot = $expanded
        $script:CodexHome = Split-Path -Parent $expanded
    }

    $script:IndexPath = Join-Path $script:CodexHome "session_index.jsonl"
    $script:ArchiveRoot = Join-Path $script:CodexHome "archived_sessions\session-cleaner"
}

Set-CodexPaths -Path $SessionPath

function Format-RelativeTime {
    param([datetime]$Value)

    $span = (Get-Date) - $Value.ToLocalTime()
    if ($span.TotalMinutes -lt 1) { return "방금" }
    if ($span.TotalHours -lt 1) { return ("{0}분 전" -f [math]::Floor($span.TotalMinutes)) }
    if ($span.TotalDays -lt 1) { return ("{0}시간 전" -f [math]::Floor($span.TotalHours)) }
    if ($span.TotalDays -lt 14) { return ("{0}일 전" -f [math]::Floor($span.TotalDays)) }
    if ($span.TotalDays -lt 70) { return ("{0}주 전" -f [math]::Floor($span.TotalDays / 7)) }
    return $Value.ToLocalTime().ToString("yyyy-MM-dd HH:mm")
}

function Format-FileSize {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N1} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N1} KB" -f ($Bytes / 1KB)) }
    return ("{0} B" -f $Bytes)
}

function Get-SessionFileMap {
    $map = @{}
    if (-not (Test-Path -LiteralPath $SessionsRoot)) { return $map }

    Get-ChildItem -LiteralPath $SessionsRoot -Recurse -File -Filter "*.jsonl" | ForEach-Object {
        if ($_.BaseName -match "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$") {
            $map[$matches[1]] = $_
        }
    }
    return $map
}

function Get-IndexRows {
    if (-not (Test-Path -LiteralPath $IndexPath)) { return @() }

    $rows = New-Object System.Collections.Generic.List[object]
    [System.IO.File]::ReadLines($IndexPath, [System.Text.Encoding]::UTF8) | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_)) { return }
        try {
            $row = $_ | ConvertFrom-Json
            if ($row.id) { $rows.Add($row) }
        } catch {
            # Preserve unreadable rows during deletion by only filtering exact, parsed IDs.
        }
    }
    return $rows
}

function Get-ProjectInfo {
    param([System.IO.FileInfo]$File)

    if (-not $File) {
        return [pscustomobject]@{
            Name = "(파일 없음)"
            Path = ""
            Key = "__missing__"
        }
    }

    $cwd = ""
    try {
        $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        $stream = [System.IO.File]::Open($File.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
        try {
            for ($i = 0; $i -lt 300 -and -not $reader.EndOfStream; $i++) {
                $line = $reader.ReadLine()
                if ($line -notlike '*"cwd"*') { continue }

                try {
                    $row = $line | ConvertFrom-Json
                    if ($row.payload -and $row.payload.cwd) {
                        $cwd = [string]$row.payload.cwd
                        break
                    }
                } catch {
                    $match = [regex]::Match($line, '"cwd"\s*:\s*"((?:\\.|[^"\\])*)"')
                    if ($match.Success) {
                        $cwd = [System.Text.RegularExpressions.Regex]::Unescape($match.Groups[1].Value)
                        break
                    }
                }
            }
        } finally {
            $reader.Close()
        }
    } catch {
        $cwd = ""
    }

    if ([string]::IsNullOrWhiteSpace($cwd)) {
        return [pscustomobject]@{
            Name = "(프로젝트 없음)"
            Path = ""
            Key = "__unknown__"
        }
    }

    $name = Split-Path -Leaf $cwd
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $cwd }

    return [pscustomobject]@{
        Name = $name
        Path = $cwd
        Key = $cwd.ToLowerInvariant()
    }
}

function Get-SessionItems {
    $fileMap = Get-SessionFileMap
    $latestById = @{}

    foreach ($row in (Get-IndexRows)) {
        $updatedAt = [datetime]::MinValue
        if ($row.updated_at) {
            [datetime]::TryParse($row.updated_at, [ref]$updatedAt) | Out-Null
        }

        if (-not $latestById.ContainsKey($row.id) -or $updatedAt -gt $latestById[$row.id].UpdatedAt) {
            $latestById[$row.id] = [pscustomobject]@{
                Id = [string]$row.id
                Title = if ($row.thread_name) { [string]$row.thread_name } else { "(제목 없음)" }
                UpdatedAt = $updatedAt
            }
        }
    }

    foreach ($id in $fileMap.Keys) {
        if (-not $latestById.ContainsKey($id)) {
            $file = $fileMap[$id]
            $latestById[$id] = [pscustomobject]@{
                Id = [string]$id
                Title = "(인덱스 없음)"
                UpdatedAt = $file.LastWriteTimeUtc
            }
        }
    }

    $items = foreach ($entry in $latestById.Values) {
        $file = if ($fileMap.ContainsKey($entry.Id)) { $fileMap[$entry.Id] } else { $null }
        $project = Get-ProjectInfo -File $file
        [pscustomobject]@{
            Id = $entry.Id
            Title = $entry.Title
            UpdatedAt = $entry.UpdatedAt
            UpdatedText = if ($entry.UpdatedAt -eq [datetime]::MinValue) { "-" } else { Format-RelativeTime $entry.UpdatedAt }
            FilePath = if ($file) { $file.FullName } else { "" }
            SizeText = if ($file) { Format-FileSize $file.Length } else { "-" }
            Exists = [bool]$file
            ProjectName = $project.Name
            ProjectPath = $project.Path
            ProjectKey = $project.Key
        }
    }

    return $items | Sort-Object UpdatedAt -Descending
}

function Backup-IndexFile {
    if (-not (Test-Path -LiteralPath $IndexPath)) { return $null }

    $backupDir = Join-Path $ArchiveRoot "index-backups"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $backupDir "session_index.$stamp.jsonl.bak"
    Copy-Item -LiteralPath $IndexPath -Destination $backupPath -Force
    return $backupPath
}

function Backup-SessionFile {
    param(
        [pscustomobject]$Item,
        [bool]$MoveFile
    )

    if (-not $Item.FilePath -or -not (Test-Path -LiteralPath $Item.FilePath)) { return $null }

    $archiveDir = Join-Path $ArchiveRoot (Get-Date -Format "yyyy-MM-dd")
    New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null
    $dest = Join-Path $archiveDir (Split-Path -Leaf $Item.FilePath)
    if (Test-Path -LiteralPath $dest) {
        $dest = Join-Path $archiveDir ("{0}.{1}.bak" -f (Split-Path -Leaf $Item.FilePath), (Get-Date -Format "HHmmss"))
    }

    if ($MoveFile) {
        Move-Item -LiteralPath $Item.FilePath -Destination $dest -Force
    } else {
        Copy-Item -LiteralPath $Item.FilePath -Destination $dest -Force
    }

    return $dest
}

function Remove-SessionFromIndex {
    param([string]$Id)

    if (-not (Test-Path -LiteralPath $IndexPath)) { return }

    $kept = New-Object System.Collections.Generic.List[string]
    [System.IO.File]::ReadLines($IndexPath, [System.Text.Encoding]::UTF8) | ForEach-Object {
        $line = $_
        if ([string]::IsNullOrWhiteSpace($line)) { return }
        try {
            $row = $line | ConvertFrom-Json
            if ([string]$row.id -ne $Id) { $kept.Add($line) }
        } catch {
            $kept.Add($line)
        }
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($IndexPath, [string[]]$kept, $utf8NoBom)
}

function Remove-Session {
    param(
        [pscustomobject]$Item,
        [bool]$DeleteForever,
        [bool]$BackupIndex = $true
    )

    if ($BackupIndex) {
        Backup-IndexFile | Out-Null
    }

    if ($Item.FilePath -and (Test-Path -LiteralPath $Item.FilePath)) {
        if ($DeleteForever) {
            Remove-Item -LiteralPath $Item.FilePath -Force
        } else {
            Backup-SessionFile -Item $Item -MoveFile $true | Out-Null
        }
    }

    Remove-SessionFromIndex -Id $Item.Id
}

function Backup-Session {
    param([pscustomobject]$Item)

    Backup-IndexFile | Out-Null
    Backup-SessionFile -Item $Item -MoveFile $false | Out-Null
}

$font = New-Object System.Drawing.Font("Segoe UI", 9)
$form = New-Object System.Windows.Forms.Form
$form.Text = "Codex Session Cleaner"
$form.Size = New-Object System.Drawing.Size(920, 620)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(780, 480)
$form.Font = $font

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = "Fill"
$layout.ColumnCount = 1
$layout.RowCount = 3
$layout.Margin = New-Object System.Windows.Forms.Padding(0)
$layout.Padding = New-Object System.Windows.Forms.Padding(0)
[void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 86)))
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))
$form.Controls.Add($layout)

$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = "Fill"
$topPanel.Height = 86
$topPanel.Padding = New-Object System.Windows.Forms.Padding(10, 9, 10, 8)
$layout.Controls.Add($topPanel, 0, 0)

$pathLabel = New-Object System.Windows.Forms.Label
$pathLabel.Text = "세션 경로"
$pathLabel.Left = 10
$pathLabel.Top = 13
$pathLabel.Width = 65
$topPanel.Controls.Add($pathLabel)

$pathBox = New-Object System.Windows.Forms.TextBox
$pathBox.Left = 80
$pathBox.Top = 10
$pathBox.Width = 575
$pathBox.Anchor = "Left,Top,Right"
$pathBox.Text = $SessionsRoot
$topPanel.Controls.Add($pathBox)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = "찾아보기"
$browseButton.Width = 85
$browseButton.Left = 665
$browseButton.Top = 8
$browseButton.Anchor = "Top,Right"
$topPanel.Controls.Add($browseButton)

$applyPathButton = New-Object System.Windows.Forms.Button
$applyPathButton.Text = "적용"
$applyPathButton.Width = 65
$applyPathButton.Left = 760
$applyPathButton.Top = 8
$applyPathButton.Anchor = "Top,Right"
$topPanel.Controls.Add($applyPathButton)

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Width = 310
$searchBox.Left = 10
$searchBox.Top = 48
$searchBox.Anchor = "Left,Top"
if ($searchBox.PSObject.Properties.Name -contains "PlaceholderText") {
    $searchBox.PlaceholderText = "제목 또는 ID 검색"
}
$topPanel.Controls.Add($searchBox)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "새로고침"
$refreshButton.Width = 90
$refreshButton.Left = 330
$refreshButton.Top = 46
$topPanel.Controls.Add($refreshButton)

$openChatButton = New-Object System.Windows.Forms.Button
$openChatButton.Text = "열기"
$openChatButton.Width = 52
$openChatButton.Left = 430
$openChatButton.Top = 46
$topPanel.Controls.Add($openChatButton)

$removeWithBackupButton = New-Object System.Windows.Forms.Button
$removeWithBackupButton.Text = "백업 후 제거"
$removeWithBackupButton.Width = 105
$removeWithBackupButton.Left = 490
$removeWithBackupButton.Top = 46
$topPanel.Controls.Add($removeWithBackupButton)

$removeButton = New-Object System.Windows.Forms.Button
$removeButton.Text = "제거"
$removeButton.Width = 58
$removeButton.Left = 603
$removeButton.Top = 46
$topPanel.Controls.Add($removeButton)

$backupButton = New-Object System.Windows.Forms.Button
$backupButton.Text = "백업"
$backupButton.Width = 58
$backupButton.Left = 669
$backupButton.Top = 46
$topPanel.Controls.Add($backupButton)

$openArchiveButton = New-Object System.Windows.Forms.Button
$openArchiveButton.Text = "백업 폴더"
$openArchiveButton.Width = 88
$openArchiveButton.Left = 735
$openArchiveButton.Top = 46
$topPanel.Controls.Add($openArchiveButton)

$list = New-Object System.Windows.Forms.ListView
$list.Dock = "Fill"
$list.View = [System.Windows.Forms.View]::Details
$list.FullRowSelect = $true
$list.HideSelection = $false
$list.MultiSelect = $true
$list.ShowGroups = $true
$list.ShowItemToolTips = $true
$list.GridLines = $false
[void]$list.Columns.Add("채팅", 430)
[void]$list.Columns.Add("수정", 90)
[void]$list.Columns.Add("크기", 90)
[void]$list.Columns.Add("ID", 250)
$layout.Controls.Add($list, 0, 1)

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$openChatMenu = New-Object System.Windows.Forms.ToolStripMenuItem("열기")
$removeWithBackupMenu = New-Object System.Windows.Forms.ToolStripMenuItem("백업 후 제거")
$removeMenu = New-Object System.Windows.Forms.ToolStripMenuItem("제거")
$backupMenu = New-Object System.Windows.Forms.ToolStripMenuItem("백업")
[void]$contextMenu.Items.Add($openChatMenu)
[void]$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$contextMenu.Items.Add($removeWithBackupMenu)
[void]$contextMenu.Items.Add($removeMenu)
[void]$contextMenu.Items.Add($backupMenu)
$list.ContextMenuStrip = $contextMenu

$status = New-Object System.Windows.Forms.StatusStrip
$status.Dock = "Fill"
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Spring = $true
$statusLabel.TextAlign = "MiddleLeft"
[void]$status.Items.Add($statusLabel)
$layout.Controls.Add($status, 0, 2)

$script:allItems = @()

function Update-Status {
    param([string]$Message)
    $statusLabel.Text = $Message
}

function Fill-List {
    $filter = $searchBox.Text.Trim()
    $list.BeginUpdate()
    $list.Items.Clear()
    $list.Groups.Clear()

    $projectGroups = @{}
    $projectCounts = @{}
    $shown = 0
    foreach ($item in $script:allItems) {
        $matchesFilter = -not $filter `
            -or $item.Title -like "*$filter*" `
            -or $item.Id -like "*$filter*" `
            -or $item.ProjectName -like "*$filter*" `
            -or $item.ProjectPath -like "*$filter*"
        if (-not $matchesFilter) { continue }

        if (-not $projectGroups.ContainsKey($item.ProjectKey)) {
            $projectGroup = New-Object System.Windows.Forms.ListViewGroup($item.ProjectName, [System.Windows.Forms.HorizontalAlignment]::Left)
            [void]$list.Groups.Add($projectGroup)
            $projectGroups[$item.ProjectKey] = $projectGroup
            $projectCounts[$item.ProjectKey] = 0
        }

        $projectCounts[$item.ProjectKey] = $projectCounts[$item.ProjectKey] + 1
        $projectGroups[$item.ProjectKey].Header = ("{0} ({1})" -f $item.ProjectName, $projectCounts[$item.ProjectKey])

        $row = New-Object System.Windows.Forms.ListViewItem($item.Title)
        $row.Group = $projectGroups[$item.ProjectKey]
        $row.Tag = $item
        $row.ToolTipText = "제목: $($item.Title)`r`n프로젝트: $($item.ProjectPath)`r`nID: $($item.Id)`r`n크기: $($item.SizeText)`r`n파일: $($item.FilePath)"
        [void]$row.SubItems.Add($item.UpdatedText)
        [void]$row.SubItems.Add($item.SizeText)
        [void]$row.SubItems.Add($item.Id)
        if (-not $item.Exists) {
            $row.ForeColor = [System.Drawing.Color]::Gray
        }
        [void]$list.Items.Add($row)
        $shown++
    }

    $list.EndUpdate()
    Update-Status ("{0}개 표시 / 전체 {1}개. 기본 삭제는 백업 폴더로 이동합니다." -f $shown, $script:allItems.Count)
}

function Get-SelectedSessionItems {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($selected in $list.SelectedItems) {
        if ($selected.Tag) { $items.Add([pscustomobject]$selected.Tag) }
    }
    return $items.ToArray()
}

function Format-SelectionSummary {
    param([object[]]$Items)

    if ($Items.Count -eq 1) {
        $item = $Items[0]
        return "프로젝트: $($item.ProjectName)`r`n제목: $($item.Title)`r`nID: $($item.Id)"
    }

    $preview = ($Items | Select-Object -First 6 | ForEach-Object { "- $($_.Title)" }) -join "`r`n"
    if ($Items.Count -gt 6) {
        $preview = "$preview`r`n... 외 $($Items.Count - 6)개"
    }
    return "선택한 채팅: $($Items.Count)개`r`n`r`n$preview"
}

function Update-SelectionStatus {
    $count = $list.SelectedItems.Count
    if ($count -gt 0) {
        Update-Status ("{0}개 선택됨. 우클릭 메뉴 또는 Delete/Enter/Ctrl+A를 사용할 수 있습니다." -f $count)
    } else {
        Update-Status ("{0}개 표시 / 전체 {1}개. 기본 삭제는 백업 폴더로 이동합니다." -f $list.Items.Count, $script:allItems.Count)
    }
}

function Open-SelectedChats {
    $items = @(Get-SelectedSessionItems)
    if ($items.Count -ne 1) {
        [System.Windows.Forms.MessageBox]::Show("열 채팅 하나만 선택하세요.", "선택 필요", "OK", "Information") | Out-Null
        return
    }

    $item = $items[0]
    if (-not $item.FilePath -or -not (Test-Path -LiteralPath $item.FilePath)) {
        [System.Windows.Forms.MessageBox]::Show("열 수 있는 세션 파일이 없습니다.`r`n$($item.FilePath)", "파일 없음", "OK", "Information") | Out-Null
        return
    }

    Start-Process notepad.exe -ArgumentList "`"$($item.FilePath)`""
    Update-Status "열기: $($item.Title)"
}

function Backup-SelectedChats {
    $items = @(Get-SelectedSessionItems)
    if ($items.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("백업할 채팅을 선택하세요.", "선택 필요", "OK", "Information") | Out-Null
        return
    }

    $message = "선택한 채팅을 백업할까요?`r`n`r`n$(Format-SelectionSummary -Items $items)"
    $result = [System.Windows.Forms.MessageBox]::Show($message, "백업 확인", "YesNo", "Question")
    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        foreach ($item in $items) {
            Backup-Session -Item $item
        }
        Update-Status "백업 완료: $($items.Count)개"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("백업 중 오류가 났습니다.`r`n$($_.Exception.Message)", "오류", "OK", "Error") | Out-Null
    }
}

function Remove-SelectedChats {
    param([bool]$DeleteForever)

    $items = @(Get-SelectedSessionItems)
    if ($items.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("삭제할 채팅을 선택하세요.", "선택 필요", "OK", "Information") | Out-Null
        return
    }

    $modeText = if ($DeleteForever) { "백업 없이 완전히 삭제" } else { "백업 폴더로 이동 후 삭제" }
    $message = "선택한 채팅을 $modeText 할까요?`r`n`r`n$(Format-SelectionSummary -Items $items)"
    $result = [System.Windows.Forms.MessageBox]::Show($message, "삭제 확인", "YesNo", "Warning")
    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        foreach ($item in $items) {
            Remove-Session -Item $item -DeleteForever $DeleteForever -BackupIndex (-not $DeleteForever)
        }
        Load-Sessions
        Update-Status "삭제 완료: $($items.Count)개"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("삭제 중 오류가 났습니다.`r`n$($_.Exception.Message)", "오류", "OK", "Error") | Out-Null
    }
}

function Load-Sessions {
    try {
        $script:allItems = @(Get-SessionItems)
        Fill-List
        if (-not (Test-Path -LiteralPath $SessionsRoot)) {
            Update-Status "세션 폴더가 없습니다: $SessionsRoot"
        } elseif (-not (Test-Path -LiteralPath $IndexPath)) {
            Update-Status "인덱스 파일 없이 세션 파일만 표시 중입니다: $IndexPath"
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("세션 목록을 읽지 못했습니다.`r`n$($_.Exception.Message)", "오류", "OK", "Error") | Out-Null
    }
}

function Apply-SessionPath {
    try {
        Set-CodexPaths -Path $pathBox.Text
        $pathBox.Text = $SessionsRoot
        Load-Sessions
    } catch {
        [System.Windows.Forms.MessageBox]::Show("경로를 적용하지 못했습니다.`r`n$($_.Exception.Message)", "오류", "OK", "Error") | Out-Null
    }
}

$refreshButton.Add_Click({ Load-Sessions })
$searchBox.Add_TextChanged({ Fill-List })
$applyPathButton.Add_Click({ Apply-SessionPath })
$pathBox.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $_.SuppressKeyPress = $true
        Apply-SessionPath
    }
})
$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = ".codex 폴더 또는 sessions 폴더를 선택하세요."
    if (Test-Path -LiteralPath $pathBox.Text) {
        $dialog.SelectedPath = $pathBox.Text
    } elseif (Test-Path -LiteralPath $SessionsRoot) {
        $dialog.SelectedPath = $SessionsRoot
    } else {
        $dialog.SelectedPath = $env:USERPROFILE
    }

    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $pathBox.Text = $dialog.SelectedPath
        Apply-SessionPath
    }
})
$openArchiveButton.Add_Click({
    New-Item -ItemType Directory -Force -Path $ArchiveRoot | Out-Null
    Start-Process explorer.exe -ArgumentList "`"$ArchiveRoot`""
})

$openChatButton.Add_Click({ Open-SelectedChats })
$removeWithBackupButton.Add_Click({ Remove-SelectedChats -DeleteForever $false })
$removeButton.Add_Click({ Remove-SelectedChats -DeleteForever $true })
$backupButton.Add_Click({ Backup-SelectedChats })
$openChatMenu.Add_Click({ Open-SelectedChats })
$removeWithBackupMenu.Add_Click({ Remove-SelectedChats -DeleteForever $false })
$removeMenu.Add_Click({ Remove-SelectedChats -DeleteForever $true })
$backupMenu.Add_Click({ Backup-SelectedChats })
$list.Add_MouseDoubleClick({ Open-SelectedChats })
$list.Add_SelectedIndexChanged({ Update-SelectionStatus })
$list.Add_MouseDown({
    if ($_.Button -ne [System.Windows.Forms.MouseButtons]::Right) { return }

    $hit = $list.HitTest($_.Location)
    if ($hit.Item -and -not $hit.Item.Selected) {
        $list.SelectedItems.Clear()
        $hit.Item.Selected = $true
        $hit.Item.Focused = $true
    }
})
$list.Add_KeyDown({
    if ($_.Control -and $_.KeyCode -eq [System.Windows.Forms.Keys]::A) {
        foreach ($item in $list.Items) { $item.Selected = $true }
        $_.SuppressKeyPress = $true
        return
    }

    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Delete) {
        $_.SuppressKeyPress = $true
        Remove-SelectedChats -DeleteForever $false
        return
    }

    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $_.SuppressKeyPress = $true
        Open-SelectedChats
    }
})
$contextMenu.Add_Opening({
    $count = $list.SelectedItems.Count
    $hasSelection = $count -gt 0
    $openChatMenu.Enabled = $count -eq 1
    $removeWithBackupMenu.Enabled = $hasSelection
    $removeMenu.Enabled = $hasSelection
    $backupMenu.Enabled = $hasSelection
})

$form.Add_Shown({ Load-Sessions })
[System.Windows.Forms.Application]::Run($form)

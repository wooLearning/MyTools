# Codex Session Cleaner

Windows GUI tool for reviewing and deleting local Codex Desktop session files.

## Features

- Loads Codex sessions from a selected `.codex` or `.codex\sessions` folder.
- Groups chats by project using the session `cwd` metadata.
- Supports multi-select with mouse, Shift/Ctrl, keyboard navigation, and Ctrl+A.
- Right-click selected chats for `열기`, `백업 후 제거`, `제거`, and `백업`.
- The top action buttons use the same action names as the right-click menu.
- Deletes one or more selected chats at a time.
- Moves deleted chats to a backup folder by default.
- `백업 후 제거` moves chats to the backup folder. `제거` deletes without creating a backup.

## Shortcuts

- `Enter`: open the selected chat transcript file.
- `Delete`: remove selected chats with backup.
- `Ctrl+A`: select all visible chats.

## Run

Double-click:

```bat
launch_session_cleaner.bat
```

Or run directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\CodexSessionCleaner.ps1
```

## Notes

Default session path:

```text
%USERPROFILE%\.codex\sessions
```

Backup folder:

```text
%USERPROFILE%\.codex\archived_sessions\session-cleaner
```

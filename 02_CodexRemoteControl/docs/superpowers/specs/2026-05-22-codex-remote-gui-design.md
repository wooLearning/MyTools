# Codex Remote GUI Design

## Goal

Build a small Windows GUI tool that toggles Codex Desktop Mobile Remote Control for a user-selected `.codex` folder.

## Scope

The tool lets the user choose or type a `.codex` folder. It derives the feature database path as:

```text
<selected .codex>\sqlite\codex-dev.db
```

The tool supports:

- `Activate`: create the `sqlite` folder, create/open `codex-dev.db`, create the feature table, and set `remote_control = 1`.
- `상태 확인`: re-read the selected database and local process/network state.
- `프롬프트 보기`: show copyable PowerShell commands and a short instruction prompt for another PC.

The GUI intentionally does not provide an off/disconnect action. Turning the database value off does not stop an already-running app-server session, and force-stopping that process can disrupt the current Codex Desktop session.

## UI

The first screen is the tool itself. It has a `.codex` path field, a `Browse` button, three status rows, and the action buttons.

Status rows are intentionally separate:

- `Selected DB`: state from the selected `.codex` database.
- `App Server`: whether the local Windows Codex Desktop app-server process is running.
- `Connection`: whether a local Codex process has an established TCP connection on remote port `443`.

## Implementation

Use Python standard library only:

- `tkinter` for GUI.
- `sqlite3` for database updates.
- `subprocess` with PowerShell for Windows process/TCP inspection.
- `unittest` for core logic tests.

Core behavior lives outside the GUI so it can be tested without opening a window.

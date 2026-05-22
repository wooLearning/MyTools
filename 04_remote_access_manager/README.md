# Remote Access Manager

Small Windows helper for opening an SSH tunnel, mounting a remote path as a local drive with SSHFS-Win, and opening a VNC viewer through a local tunnel.

## Local Setup

1. Copy `config.example.json` to `config.local.json`.
2. Fill in your local jump host, target host, users, remote path, and preferred drive letter.
3. Leave passwords out of `config.local.json`. The manager asks for them at run time.

`config.local.json`, logs, archives, and Windows shortcuts are ignored by git.

## Run

Open the manager:

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\T_Drive_Manager.ps1
```

Mount the configured drive directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\mount_T_now.ps1 -OpenExplorer
```

Unmount:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\unmount_T.ps1
```

## Notes

- `config.example.json` is safe to publish.
- `config.local.json` is local only.
- Password fields in the manager are passed only to the child process environment for the current run.
- If key authentication is available, leave the password fields blank.
- The optional logon restore shortcut lives in the current user's Startup folder as `Remote Access Restore.lnk`.

# Handoff Prompt: Remote Access Manager

This folder contains a generic Windows helper for SSH tunnel, SSHFS drive mount, and VNC tunnel workflows.

Sensitive or environment-specific values must live in `config.local.json`, which is excluded by `.gitignore`.

Repo-safe files should not contain real user names, hostnames, passwords, private paths, or generated logs.

Primary commands:

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\T_Drive_Manager.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\mount_T_now.ps1 -OpenExplorer
powershell -NoProfile -ExecutionPolicy Bypass -File .\unmount_T.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\status_check.ps1
```

Local setup:

```powershell
Copy-Item .\config.example.json .\config.local.json
notepad .\config.local.json
```

Do not commit `config.local.json`, `logs/`, `archive/`, or `*.lnk`.

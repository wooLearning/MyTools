# Codex Remote GUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a small Windows GUI that activates and checks Codex Mobile Remote Control for a selected `.codex` folder.

**Architecture:** Keep state-changing logic in `core.py` and UI wiring in `app.py`. The GUI calls core functions for path resolution, SQLite updates, status checks, and prompt generation.

**Tech Stack:** Python standard library: `tkinter`, `sqlite3`, `subprocess`, `unittest`.

---

### Task 1: Core Tests

**Files:**
- Create: `codex_remote_gui/tests/test_core.py`
- Create: `codex_remote_gui/__init__.py`

- [ ] Test `.codex` path resolution from a selected folder.
- [ ] Test `init_remote_control`, `set_remote_control`, and `read_remote_control`.
- [ ] Test generated prompt uses the selected `.codex` path.

### Task 2: Core Logic

**Files:**
- Create: `codex_remote_gui/core.py`

- [ ] Implement path resolution.
- [ ] Implement SQLite table creation and upsert.
- [ ] Implement DB status reading.
- [ ] Implement Windows process and TCP status checks through PowerShell.
- [ ] Implement copyable prompt generation.

### Task 3: GUI

**Files:**
- Create: `codex_remote_gui/app.py`
- Create: `codex_remote_gui/run_codex_remote_gui.bat`

- [ ] Implement a compact Tkinter window.
- [ ] Add `.codex` path input and folder browse.
- [ ] Add `Activate`, `상태 확인`, and `프롬프트 보기`.
- [ ] Refresh status after actions.

### Task 4: Verification

**Commands:**

```powershell
python -m unittest discover -s codex_remote_gui\tests -v
python -m py_compile codex_remote_gui\core.py codex_remote_gui\app.py
```

Expected result: tests pass and both files compile.

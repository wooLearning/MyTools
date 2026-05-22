from __future__ import annotations

import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

try:
    from . import core
except ImportError:
    import core


class CodexRemoteApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Codex Remote Control")
        self.minsize(620, 330)

        self.codex_dir_var = tk.StringVar(value=str(core.default_codex_dir()))
        self.db_path_var = tk.StringVar(value="")
        self.db_status_var = tk.StringVar(value="Unknown")
        self.server_status_var = tk.StringVar(value="Unknown")
        self.connection_status_var = tk.StringVar(value="Unknown")
        self.message_var = tk.StringVar(value="Ready")

        self._build_ui()
        self.refresh_status()

    def _build_ui(self) -> None:
        self.columnconfigure(0, weight=1)

        outer = ttk.Frame(self, padding=16)
        outer.grid(row=0, column=0, sticky="nsew")
        outer.columnconfigure(1, weight=1)

        title = ttk.Label(outer, text="Codex Remote Control", font=("Segoe UI", 16, "bold"))
        title.grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 14))

        ttk.Label(outer, text=".codex folder").grid(row=1, column=0, sticky="w", padx=(0, 8))
        path_entry = ttk.Entry(outer, textvariable=self.codex_dir_var)
        path_entry.grid(row=1, column=1, sticky="ew", padx=(0, 8))
        ttk.Button(outer, text="Browse", command=self.choose_folder).grid(row=1, column=2, sticky="ew")

        ttk.Label(outer, text="DB path").grid(row=2, column=0, sticky="w", padx=(0, 8), pady=(8, 0))
        ttk.Label(outer, textvariable=self.db_path_var, foreground="#555555").grid(
            row=2, column=1, columnspan=2, sticky="w", pady=(8, 0)
        )

        status_frame = ttk.LabelFrame(outer, text="Status", padding=12)
        status_frame.grid(row=3, column=0, columnspan=3, sticky="ew", pady=(16, 12))
        status_frame.columnconfigure(1, weight=1)

        self._status_row(status_frame, 0, "Selected DB", self.db_status_var)
        self._status_row(status_frame, 1, "App Server", self.server_status_var)
        self._status_row(status_frame, 2, "Connection", self.connection_status_var)

        button_frame = ttk.Frame(outer)
        button_frame.grid(row=4, column=0, columnspan=3, sticky="ew")
        for col in range(3):
            button_frame.columnconfigure(col, weight=1)

        ttk.Button(button_frame, text="Activate", command=self.activate_remote).grid(
            row=0, column=0, sticky="ew", padx=(0, 6)
        )
        ttk.Button(button_frame, text="상태 확인", command=self.refresh_status).grid(
            row=0, column=1, sticky="ew", padx=6
        )
        ttk.Button(button_frame, text="프롬프트 보기", command=self.show_prompt).grid(
            row=0, column=2, sticky="ew", padx=(6, 0)
        )

        ttk.Label(outer, textvariable=self.message_var, foreground="#555555").grid(
            row=5, column=0, columnspan=3, sticky="w", pady=(14, 0)
        )

    def _status_row(self, parent: ttk.Frame, row: int, label: str, variable: tk.StringVar) -> None:
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", padx=(0, 12), pady=3)
        ttk.Label(parent, textvariable=variable).grid(row=row, column=1, sticky="w", pady=3)

    def selected_codex_dir(self) -> Path:
        value = self.codex_dir_var.get().strip()
        if not value:
            raise ValueError("Select or type a .codex folder path first.")
        return core.normalize_codex_dir(value)

    def choose_folder(self) -> None:
        folder = filedialog.askdirectory(
            title="Select .codex folder",
            initialdir=str(Path.home()),
            mustexist=False,
        )
        if folder:
            self.codex_dir_var.set(folder)
            self.refresh_status()

    def activate_remote(self) -> None:
        try:
            db_path = core.init_remote_control(self.selected_codex_dir())
            self.message_var.set(f"Remote Control activated: {db_path}")
            self.refresh_status()
        except Exception as exc:
            messagebox.showerror("Activate failed", str(exc))

    def refresh_status(self) -> None:
        try:
            codex_dir = self.selected_codex_dir()
            db_path = core.db_path_for_codex_dir(codex_dir)
            self.db_path_var.set(str(db_path))

            db_value = core.read_remote_control(codex_dir)
            if db_value is None:
                self.db_status_var.set("Not initialized")
            elif db_value == 1:
                self.db_status_var.set("ON")
            else:
                self.db_status_var.set("OFF")

            runtime = core.inspect_runtime_status()
            self.server_status_var.set(_format_running(runtime.app_server_running, runtime.app_server_pids))
            self.connection_status_var.set(_format_connected(runtime.cloud_connected, runtime.connected_pids))
            if runtime.error:
                self.message_var.set(f"Status check warning: {runtime.error}")
            elif self.message_var.get() == "Ready":
                self.message_var.set("Status loaded")
        except Exception as exc:
            self.db_status_var.set("Unknown")
            self.server_status_var.set("Unknown")
            self.connection_status_var.set("Unknown")
            self.message_var.set(str(exc))

    def show_prompt(self) -> None:
        try:
            prompt = core.build_prompt_text(self.selected_codex_dir())
        except Exception as exc:
            messagebox.showerror("Prompt failed", str(exc))
            return

        window = tk.Toplevel(self)
        window.title("프롬프트 보기")
        window.geometry("760x520")
        window.columnconfigure(0, weight=1)
        window.rowconfigure(0, weight=1)

        text_frame = ttk.Frame(window, padding=12)
        text_frame.grid(row=0, column=0, sticky="nsew")
        text_frame.columnconfigure(0, weight=1)
        text_frame.rowconfigure(0, weight=1)

        text = tk.Text(text_frame, wrap="word", font=("Consolas", 10))
        text.grid(row=0, column=0, sticky="nsew")
        scrollbar = ttk.Scrollbar(text_frame, orient="vertical", command=text.yview)
        scrollbar.grid(row=0, column=1, sticky="ns")
        text.configure(yscrollcommand=scrollbar.set)
        text.insert("1.0", prompt)

        actions = ttk.Frame(window, padding=(12, 0, 12, 12))
        actions.grid(row=1, column=0, sticky="ew")
        actions.columnconfigure(0, weight=1)

        ttk.Button(actions, text="Copy", command=lambda: self.copy_prompt(prompt)).grid(row=0, column=1, padx=(0, 8))
        ttk.Button(actions, text="Close", command=window.destroy).grid(row=0, column=2)

    def copy_prompt(self, prompt: str) -> None:
        self.clipboard_clear()
        self.clipboard_append(prompt)
        self.message_var.set("Prompt copied to clipboard")


def _format_running(running: bool, pids: tuple[int, ...]) -> str:
    if not running:
        return "Not running"
    return f"Running (PID {', '.join(str(pid) for pid in pids)})"


def _format_connected(connected: bool, pids: tuple[int, ...]) -> str:
    if not connected:
        return "Not connected"
    return f"Connected (PID {', '.join(str(pid) for pid in pids)})"


def main() -> None:
    app = CodexRemoteApp()
    app.mainloop()


if __name__ == "__main__":
    main()

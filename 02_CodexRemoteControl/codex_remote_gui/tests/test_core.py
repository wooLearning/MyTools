import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path

from codex_remote_gui import core


class CoreTests(unittest.TestCase):
    def test_db_path_uses_selected_codex_folder(self):
        codex_dir = Path(r"C:\Users\someone\.codex")

        self.assertEqual(
            core.db_path_for_codex_dir(codex_dir),
            codex_dir / "sqlite" / "codex-dev.db",
        )

    def test_init_activates_and_read_remote_control(self):
        with tempfile.TemporaryDirectory() as tmp:
            codex_dir = Path(tmp) / ".codex"

            core.init_remote_control(codex_dir)
            self.assertEqual(core.read_remote_control(codex_dir), 1)

            with closing(sqlite3.connect(core.db_path_for_codex_dir(codex_dir))) as con:
                row = con.execute(
                    "select enabled from local_app_server_feature_enablement where feature_name = ?",
                    ("remote_control",),
                ).fetchone()
            self.assertEqual(row, (1,))

    def test_read_remote_control_reports_missing_database(self):
        with tempfile.TemporaryDirectory() as tmp:
            codex_dir = Path(tmp) / ".codex"

            self.assertIsNone(core.read_remote_control(codex_dir))

    def test_prompt_is_generalized_without_selected_private_path(self):
        codex_dir = Path(r"D:\portable\some-user\.codex")

        prompt = core.build_prompt_text(codex_dir)

        self.assertNotIn("D:\\portable\\some-user\\.codex", prompt)
        self.assertIn("$codexDir = Join-Path $env:USERPROFILE '.codex'", prompt)
        self.assertIn("직접 다른 `.codex` 폴더를 지정해야 한다면", prompt)
        self.assertIn("remote_control", prompt)
        self.assertIn("local_app_server_feature_enablement", prompt)


if __name__ == "__main__":
    unittest.main()

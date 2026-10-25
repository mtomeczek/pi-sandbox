"""Offline tests for shared profile management. No credentials or network needed."""

import argparse
import contextlib
import importlib.util
import io
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("manager", Path(__file__).resolve().parents[1] / "scripts/profile-manager.py")
assert spec and spec.loader
manager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manager)


class ProfileManagerTests(unittest.TestCase):
    def entries(self, text):
        return manager.parse_text(text)[1]

    def test_dependencies_and_malformed_tools(self):
        for text in ("TOOL=python@3.13.0", "TOOL=\x16playwright@1.64.0", "TOOL=unknown@1.2.3", "TOOL=go@1.2.3\nTOOL=go@1.3.0", "EXTENSION=cargo:tool@1.0.0"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                manager.validate(self.entries(text))
        manager.validate(self.entries("TOOL=uv@0.8.9\nTOOL=python@3.13.0"))

    def test_npm_and_secrets(self):
        manager.validate(self.entries("NPM=@playwright/test@^1.64.0\nNPM=playwright@>=1.2.3 <2\nENV_SECRET=API_TOKEN=secret-name\nENV=URL=a=b"))
        for text in ("NPM=bad;command", "ENV_SECRET=TOKEN=bad,type=mount", "ENV=TOKEN=\"private\"", "APT=curl;bad", "SHELL_COMMAND=echo a\\"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                manager.validate(self.entries(text))

    def test_offline_and_online_validation(self):
        with patch.object(manager, "available") as available:
            manager.validate(self.entries("TOOL=go@1.27.3"))
            available.assert_not_called()
            manager.validate(self.entries("TOOL=go@1.27.3"), online=True)
            available.assert_called_once_with("go", "1.27.3")
        with patch.object(manager, "available", side_effect=RuntimeError("private-token")):
            with self.assertRaisesRegex(ValueError, "upstream verification failed") as result:
                manager.validate(self.entries("TOOL=go@1.27.3"), online=True)
            self.assertNotIn("private-token", str(result.exception))

    def test_compatibility_ranges(self):
        with patch.object(manager, "candidates", return_value=["1.2.4", "1.3.0", "2.0.0", "1.4.0-beta"]), contextlib.redirect_stdout(io.StringIO()):
            entries = self.entries("TOOL=go@1.2.3")
            self.assertEqual(manager.audit(entries)[0][3], "1.3.0")
            self.assertEqual(manager.audit(entries, patch_only=True)[0][3], "1.2.4")
            self.assertEqual(manager.audit(self.entries("PI_VERSION=latest")), [])

    def test_atomic_upgrade_backup_and_preview(self):
        original = "# keep this comment\nTOOL=go@1.2.3\nENV_SECRET=API_TOKEN=private-reference\n"
        with tempfile.TemporaryDirectory() as directory, patch.object(manager, "candidates", return_value=["1.2.4"]), contextlib.redirect_stdout(io.StringIO()):
            path = Path(directory) / "test.profile"
            path.write_bytes(original.encode("utf-8"))
            changes = manager.audit(self.entries(original))
            manager.upgrade(str(path), original, changes, dry_run=True)
            self.assertEqual(path.read_text(), original)
            self.assertEqual(len(list(Path(directory).glob("*.bak-*"))), 0)
            with patch("sys.stdin.isatty", return_value=False), self.assertRaises(ValueError):
                manager.upgrade(str(path), original, changes)
            manager.upgrade(str(path), original, changes, yes=True)
            self.assertIn("TOOL=go@1.2.4", path.read_text())
            self.assertIn("ENV_SECRET=API_TOKEN=private-reference", path.read_text())
            backups = list(Path(directory).glob("*.bak-*"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), original)
            with self.assertRaisesRegex(ValueError, "changed while checking"):
                manager.upgrade(str(path), original, changes, yes=True)

    def test_upgrade_preserves_crlf(self):
        original = "# comment\r\nTOOL=go@1.2.3\r\nENV_SECRET=TOKEN=secret-name\r\n"
        with tempfile.TemporaryDirectory() as directory, patch.object(manager, "candidates", return_value=["1.2.4"]), contextlib.redirect_stdout(io.StringIO()):
            path = Path(directory) / "test.profile"
            path.write_bytes(original.encode())
            text, entries = manager.read_profile(str(path))
            manager.upgrade(str(path), text, manager.audit(entries), yes=True)
            self.assertEqual(path.read_bytes(), original.replace("1.2.3", "1.2.4").encode())

    def test_https_only(self):
        with self.assertRaises(ValueError):
            manager.request("file:///private-token")

    def test_no_partial_updates_when_upstream_fails(self):
        with patch.object(manager, "candidates", side_effect=RuntimeError("secret-http-body")), contextlib.redirect_stdout(io.StringIO()), self.assertRaises(ValueError) as result:
            manager.audit(self.entries("TOOL=go@1.2.3"))
        self.assertNotIn("secret-http-body", str(result.exception))

    def test_doctor_is_read_only_and_reports_missing_secrets(self):
        calls = []
        def run(command, **kwargs):
            calls.append(command)
            data = '{"host":{"security":{"rootless":true}}}' if command[1] == "info" else '[{"Config":{"Labels":{"io.pi-sandbox.template-version":"2","io.pi-sandbox.capabilities":"glab-device"}}}]'
            return subprocess.CompletedProcess(command, 1 if command[1] == "secret" else 0, data, "private-error")
        args = argparse.Namespace(image="test", secret=["token-reference"], port=[])
        output = io.StringIO()
        with patch.object(manager.shutil, "which", return_value="podman"), patch.object(manager.subprocess, "run", side_effect=run), contextlib.redirect_stdout(output):
            self.assertEqual(manager.doctor(args), 1)
        self.assertTrue(all(command[1] in {"info", "image", "secret"} for command in calls))
        self.assertNotIn("private-error", output.getvalue())
        self.assertIn("referenced Podman secret exists", output.getvalue())


if __name__ == "__main__":
    unittest.main()

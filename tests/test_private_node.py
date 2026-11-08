#!/usr/bin/env python3
"""Private-runtime launcher and build-only installer snapshot regression tests."""
import http.client
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")
NODE = shutil.which("node")


class PrivateNodeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pi-private-node-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.agent = self.directory / "agent"
        (self.agent / "install").mkdir(parents=True)
        (self.agent / "install/current-version").write_bytes(b"1.4.0\n")

    def shell(self, script, *arguments, env=None):
        assert BASH is not None
        return subprocess.run(
            [BASH, script, *arguments], cwd=self.directory,
            env=env, capture_output=True, text=True, timeout=20,
        )

    def fixture(self, name):
        source = (ROOT / "scripts/image" / name).read_text(encoding="utf-8")
        target = self.directory / name
        target.write_bytes((source.replace("/opt/pi/node/bin/node", "./private-node")).encode("utf-8"))
        return "./" + name

    @unittest.skipUnless(BASH, "Bash is not installed")
    def test_pi_keeps_project_node_and_arguments(self):
        launcher = self.fixture("pi.sh")
        private = self.directory / "private-node"
        private.write_bytes(b'#!/bin/sh\nprintf "%s\\n" "private-runtime" "$@" "PROJECT=$(node --version)"\n')
        private.chmod(0o755)
        legacy = self.directory / "legacy"
        legacy.mkdir()
        (legacy / "node").write_bytes(b'#!/bin/sh\necho v14.21.3\n')
        (legacy / "node").chmod(0o755)
        env = dict(os.environ, PI_SANDBOX_AGENT_DIR=self.agent.as_posix())
        # Let Bash construct PATH so Windows drive letters are not separators.
        result = self.shell("-c", 'export PATH="./legacy:$PATH"; exec sh "$@"', "test", launcher, "argument with spaces", "--version", env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[0], "private-runtime")
        self.assertTrue(lines[1].endswith("/install/releases/1.4.0/node_modules/.bin/pi"))
        self.assertEqual(lines[2:], ["argument with spaces", "--version", "PROJECT=v14.21.3"])

    @unittest.skipUnless(BASH, "Bash is not installed")
    def test_invalid_managed_version_rejected(self):
        (self.agent / "install/current-version").write_bytes(b"../../other\n")
        result = self.shell(self.fixture("pi.sh"), env=dict(os.environ, PI_SANDBOX_AGENT_DIR=self.agent.as_posix()))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid managed Pi version", result.stderr)

    @unittest.skipUnless(BASH, "Bash is not installed")
    def test_missing_state_does_not_change_install_location(self):
        (self.agent / "install/current-version").unlink()
        result = self.shell(self.fixture("pi.sh"), env=dict(os.environ, PI_SANDBOX_AGENT_DIR=self.agent.as_posix()))
        self.assertNotEqual(result.returncode, 0)

    @unittest.skipUnless(sys.platform.startswith("linux") and BASH, "Requires Linux image utilities")
    def test_npm_wrappers_preserve_links_and_handle_spaces(self):
        launcher = self.fixture("wrap-node-tools.sh")
        prefix = self.directory / "tools with spaces"
        (prefix / "bin").mkdir(parents=True)
        (prefix / "lib").mkdir()
        (prefix / "lib/cli.js").write_bytes(b"#!/usr/bin/env node\n")
        (prefix / "lib/script.sh").write_bytes(b"#!/bin/sh\n")
        (prefix / "bin/tool").symlink_to("../lib/cli.js")
        (prefix / "bin/shell-tool").symlink_to("../lib/script.sh")
        for _ in range(2):
            result = self.shell(launcher, str(prefix))
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((prefix / "bin/tool").is_symlink())
        wrapper = prefix / "node-bin/tool"
        self.assertTrue(wrapper.is_file())
        self.assertFalse((prefix / "node-bin/shell-tool").exists())
        private = self.directory / "private-node"
        private.write_bytes(b'#!/bin/sh\nprintf "%s\\n" "$@"\n')
        private.chmod(0o755)
        result = self.shell(str(wrapper), "argument with spaces")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [str(prefix / "lib/cli.js"), "argument with spaces"])

    @unittest.skipUnless(NODE, "Node is not installed on the test host")
    def test_installer_snapshot_is_pinned_and_rejects_other_routes(self):
        for name in ("package.json", "package-lock.json"):
            (self.directory / name).write_bytes(b'{"fixture":true}')
        assert NODE is not None
        server = subprocess.Popen(
            [NODE, str(ROOT / "scripts/image/installer-server.cjs"), str(self.directory), "1.4.0"],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        )
        try:
            port_file = self.directory / "port"
            deadline = time.monotonic() + 20
            while not port_file.exists() or port_file.stat().st_size == 0:
                self.assertIsNone(server.poll(), "Snapshot server exited")
                self.assertLess(time.monotonic(), deadline, "Snapshot server did not start")
                time.sleep(0.05)
            connection = http.client.HTTPConnection("127.0.0.1", int(port_file.read_text(encoding="utf-8")), timeout=5)
            try:
                for route, expected in (("/latest", {"version": "1.4.0"}), ("/1.4.0/package.json", {"fixture": True}), ("/1.4.0/package-lock.json", {"fixture": True})):
                    connection.request("GET", route)
                    response = connection.getresponse()
                    self.assertEqual(response.status, 200)
                    self.assertEqual(json.loads(response.read()), expected)
                for method, route in (("GET", "/1.5.0/package.json"), ("GET", "/../package.json"), ("GET", "/port"), ("POST", "/latest")):
                    connection.request(method, route)
                    response = connection.getresponse()
                    self.assertEqual(response.status, 404)
                    response.read()
            finally:
                connection.close()
        finally:
            server.terminate()
            server.wait(timeout=5)
            if server.stderr is not None:
                server.stderr.close()


if __name__ == "__main__":
    unittest.main()

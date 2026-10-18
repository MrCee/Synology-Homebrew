import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("fallback", ROOT / "compile-macos-packages.py")
fallback = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fallback)


class CompileFallbackTests(unittest.TestCase):
    def test_only_confirmed_missing_bottles_are_eligible(self):
        rows = [
            {"package": "missing", "status": "failed", "source_required": True},
            {"package": "network", "status": "failed", "source_required": False},
            {"package": "checksum", "status": "failed"},
            {"package": "ready", "status": "upstream binary"},
        ]
        self.assertEqual(fallback.source_failures(rows), ["missing"])

    def test_cli_requires_explicit_approval(self):
        result = subprocess.run([sys.executable, str(ROOT / "compile-macos-packages.py"), "jq"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("--allow-source-builds", result.stderr)

    def test_old_intel_queue_cannot_resume_without_approval(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            bin_dir = home / "bin"
            bin_dir.mkdir()
            uname = bin_dir / "uname"
            uname.write_text('#!/bin/bash\nif [[ "$1" == -m ]]; then echo x86_64; else echo Darwin; fi\n')
            uname.chmod(0o755)
            state = home / ".local/share/synology-homebrew/background"
            job = state / "jobs/old"
            job.mkdir(parents=True)
            (state / "latest").write_text(str(job))
            environment = dict(os.environ, HOME=str(home), PATH=str(bin_dir) + ":/usr/bin:/bin")
            result = subprocess.run(["/bin/bash", str(ROOT / "background-packages.sh"), "resume"],
                                    env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("no explicit source-build approval", result.stdout + result.stderr)

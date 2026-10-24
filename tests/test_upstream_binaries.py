"""Offline regression checks for binary installation integrity and collisions."""
import hashlib
import importlib.util
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("upstream", Path(__file__).resolve().parents[1] / "upstream_binaries.py")
upstream = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upstream)


class BinaryInstallTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.binary = self.root / "release"
        self.binary.write_bytes(b"#!/bin/sh\necho test\n")
        self.store = self.root / "store"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.item = {"version": "1", "url": self.binary.as_uri(), "raw": True,
                     "sha256": hashlib.sha256(self.binary.read_bytes()).hexdigest(),
                     "executables": {"test-command": "test-command"}}
        self.patch = patch.multiple(upstream, STORE=self.store, BIN=self.bin, MANIFEST={"test": self.item})
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def test_missing_zstd_bootstraps_only_a_prebuilt_decoder(self):
        with patch.dict('sys.modules', {'compression': None}), \
             patch.object(upstream.shutil, 'which', return_value=None), \
             patch.object(upstream.subprocess, 'run') as run:
            run.return_value.returncode = 1
            upstream.decompress_zstd(self.root/'payload.zst', self.root/'payload.tar')
        commands = [call.args[0] for call in run.call_args_list]
        installs = [command for command in commands if 'pip' in command]
        self.assertEqual(len(installs), 1)
        self.assertIn('--only-binary=:all:', installs[0])
        self.assertIn('--no-deps', installs[0])
        self.assertIn('zstandard==0.25.0', installs[0])
        self.assertFalse(any(command[0] == '/usr/local/bin/zstd' for command in commands))

    def test_bad_checksum_never_installs_or_links(self):
        self.item["sha256"] = "0" * 64
        with self.assertRaisesRegex(RuntimeError, "SHA256 mismatch"):
            upstream.install("test")
        self.assertFalse((self.store / "test-1").exists())
        self.assertFalse((self.bin / "test-command").exists())

    def test_existing_command_is_preserved(self):
        existing = self.bin / "test-command"
        existing.write_text("user command")
        with self.assertRaisesRegex(RuntimeError, "Refusing to replace"):
            upstream.install("test")
        self.assertEqual(existing.read_text(), "user command")

    def test_verified_install_can_be_repeated(self):
        upstream.install("test")
        upstream.install("test")
        self.assertEqual((self.bin / "test-command").resolve(), (self.store / "test-1/test-command").resolve())


if __name__ == "__main__":
    unittest.main()

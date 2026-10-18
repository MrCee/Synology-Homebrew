import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class IntelRoutingTests(unittest.TestCase):
    def test_only_macos_intel_selects_binary_installer(self):
        entry = (ROOT / 'install-synology-homebrew.sh').read_text().split('# -----------------------------------------------------------------------------', 1)[0]
        for system, arch, expected in [('Darwin', 'x86_64', 37), ('Darwin', 'arm64', 23), ('Linux', 'x86_64', 23)]:
            with self.subTest(system=system, arch=arch), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                (root/'entry.sh').write_text(entry+'\nexit 23\n')
                (root/'uname').write_text('#!/bin/sh\nif [ "$1" = -s ]; then echo '+system+'; else echo '+arch+'; fi\n')
                (root/'python3').write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$ROUTE_LOG"\nexit 37\n')
                for name in ('uname','python3'):
                    (root/name).chmod(0o755)
                result = subprocess.run(['/bin/bash', str(root/'entry.sh'), '--plan'],
                    env=dict(os.environ, PATH=tmp+':/usr/bin:/bin', ROUTE_LOG=str(root/'calls'), SYNOBREW_PYTHON=str(root/'python3')), capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stderr)
                if expected == 37:
                    self.assertEqual((root/'calls').read_text().splitlines(), [str(root/'install-macos-binaries.py'), '--plan'])
                else:
                    self.assertFalse((root/'calls').exists())

    def test_default_intel_entry_does_not_skip_interactive_installer(self):
        entry = (ROOT / 'install-synology-homebrew.sh').read_text().split('# -----------------------------------------------------------------------------', 1)[0]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root/'entry.sh').write_text(entry+'\necho original-interactive-flow\n')
            (root/'uname').write_text('#!/bin/sh\nif [ "$1" = -s ]; then echo Darwin; else echo x86_64; fi\n')
            (root/'uname').chmod(0o755)
            result = subprocess.run(['/bin/bash', str(root/'entry.sh')], env=dict(os.environ, PATH=tmp+':/usr/bin:/bin'), capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('original-interactive-flow', result.stdout)

    def test_plan_lists_routes_without_homebrew(self):
        result = subprocess.run(['/usr/local/bin/python3', str(ROOT/'install-macos-binaries.py'), '--plan', 'node', 'perl', 'thefuck', 'make'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for phrase in ('nodejs.org', 'Apple system Perl', 'wheels only', 'guarded Homebrew bottle'):
            self.assertIn(phrase, result.stdout)

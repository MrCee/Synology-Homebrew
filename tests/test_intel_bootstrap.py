"""Exercise clean Intel bootstrap without sudo, downloads or host changes."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class IntelBootstrapTests(unittest.TestCase):
    def run_shell(self, body, environment=None):
        with tempfile.TemporaryDirectory() as temporary:
            env = dict(os.environ, TEST_ROOT=temporary)
            env.update(environment or {})
            return subprocess.run(
                ['/bin/bash', '-c', 'source "$1/functions.sh"\n' + body, 'test', str(ROOT)],
                env=env, capture_output=True, text=True,
            )

    def test_sudo_denial_stops_before_downloading_homebrew(self):
        result = self.run_shell('''
func_initialize_env_vars() { DARWIN=1; HOMEBREW_PATH="$TEST_ROOT"; }
sudo() { echo "AUTH $*"; return 1; }
curl() { echo UNEXPECTED_DOWNLOAD; }
func_ensure_homebrew
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('AUTH -v', result.stdout)
        self.assertNotIn('UNEXPECTED_DOWNLOAD', result.stdout)
        self.assertIn('Unable to authenticate sudo', result.stderr)

    def test_selected_working_python_is_exported_without_install(self):
        result = self.run_shell('''
printf '#!/bin/sh\nexit 0\n' > "$TEST_ROOT/python"
chmod +x "$TEST_ROOT/python"
SYNOBREW_PYTHON="$TEST_ROOT/python"
func_install_intel_python_pkg() { echo UNEXPECTED_INSTALL; return 1; }
func_bootstrap_intel_python || exit 1
export -p | /usr/bin/grep SYNOBREW_PYTHON
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('SYNOBREW_PYTHON=', result.stdout)
        self.assertNotIn('UNEXPECTED_INSTALL', result.stdout)

    def test_missing_or_old_python_bootstraps_and_exports_framework_runtime(self):
        result = self.run_shell('''
printf '#!/bin/sh\nexit 1\n' > "$TEST_ROOT/python"
chmod +x "$TEST_ROOT/python"
SYNOBREW_PYTHON="$TEST_ROOT/python"
# Hide installed Python candidates without changing any real executables.
/usr/local/bin/python3() { return 1; }
command() { [[ "$*" == '-v python3' ]] && echo "$TEST_ROOT/python"; }
func_install_intel_python_pkg() { echo PACKAGE_INSTALLED; }
/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13() { return 0; }
func_bootstrap_intel_python || exit 1
export -p | /usr/bin/grep SYNOBREW_PYTHON
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('PACKAGE_INSTALLED', result.stdout)
        self.assertIn('/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13', result.stdout)

    def test_python_download_checksum_failure_never_runs_installer(self):
        result = self.run_shell('''
curl() { echo DOWNLOAD; return 0; }
shasum() { echo BAD_CHECKSUM >&2; return 1; }
sudo() { echo UNEXPECTED_INSTALL; return 0; }
func_install_intel_python_pkg
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('BAD_CHECKSUM', result.stderr)
        self.assertNotIn('UNEXPECTED_INSTALL', result.stdout)


if __name__ == '__main__':
    unittest.main()

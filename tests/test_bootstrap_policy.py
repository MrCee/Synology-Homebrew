"""Exercise bootstrap policy without installing packages or changing user files.

Run with: python3 -m unittest discover -s tests
"""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


class BootstrapPolicyTests(unittest.TestCase):
    def run_bootstrap(self, platform, arch, fail_package="", packages_ready=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "bin").mkdir()
            (root / "profile-templates").mkdir()
            for name in ("macos-profile-template", "synology-profile-template"):
                (root / "profile-templates" / name).write_text("# isolated profile\n")
            brew = root / "bin" / "brew"
            brew.write_text('''#!/bin/bash
printf '%s\n' "$*" >> "$TEST_LOG"
if [[ "$1" == install && "$3" == "$TEST_FAIL_PACKAGE" ]]; then
    echo "Simulated package failure: $3" >&2
    exit 1
fi
exit 0
''')
            brew.chmod(0o755)
            environment = os.environ.copy()
            environment.update(
                HOME=temporary,
                PATH=str(root / "bin") + ":/usr/bin:/bin",
                TEST_ROOT=temporary,
                TEST_LOG=str(root / "calls"),
                TEST_PLATFORM=platform,
                TEST_ARCH=arch,
                TEST_FAIL_PACKAGE=fail_package,
                INSTALL_MODE="advanced",
                SYNOBREW_PACKAGES_READY="1" if packages_ready else "0",
                HOMEBREW_TEMP=str(root / "tmp"),
            )
            script = '''uname() {
    if [[ "$1" == -s ]]; then echo "$TEST_PLATFORM"; else echo "$TEST_ARCH"; fi
}
source "$1/functions.sh"
# These tests exercise the legacy baseline loop using only a fake brew.
# Machine entry routing and build refusal have separate regression tests.
brew() { command brew "$@"; }
func_initialize_env_vars() {
    DARWIN=0
    [[ "$TEST_PLATFORM" == Darwin ]] && DARWIN=1
    HOMEBREW_PATH="$TEST_ROOT"
    return 0
}
func_bootstrap_intel_python() { return 0; }
func_bootstrap_yq() {
    echo standalone-yq-ready >> "$TEST_LOG"
    return 0
}
if install_brew_and_packages; then exit 0; else exit 1; fi
'''
            result = subprocess.run(
                ["/bin/bash", "-c", script, "test", str(REPO)],
                cwd=root, env=environment, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return (root / "calls").read_text().splitlines(), result

    def test_brew_wrapper_does_not_hide_missing_homebrew(self):
        for installed in (False, True):
            with self.subTest(installed=installed), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                (root / "bin").mkdir()
                brew = root / "bin" / "brew"
                if installed:
                    brew.write_text("#!/bin/bash\nexit 0\n")
                    brew.chmod(0o755)
                script = r'''source "$1/functions.sh"
func_initialize_env_vars() {
    DARWIN=1
    HOMEBREW_PATH="$TEST_ROOT"
}
# Match the Intel wrapper: command -v succeeds without an installed brew.
brew() { echo wrapper-must-not-run >&2; return 1; }
func_homebrew_installer_url() { echo https://example.invalid/HEAD/install.sh; }
curl() {
    echo installer-downloaded >&2
    printf '%s\n' '#!/bin/bash' 'printf "#!/bin/bash\\nexit 0\\n" > "$TEST_ROOT/bin/brew"' 'chmod +x "$TEST_ROOT/bin/brew"'
}
sudo() { echo "sudo $*" >&2; return "${TEST_SUDO_RESULT:-0}"; }
func_bootstrap_intel_python() { echo python-ready >&2; }
func_ensure_homebrew
'''
                result = subprocess.run(
                    ["/bin/bash", "-c", script, "test", str(REPO)],
                    env=dict(os.environ, TEST_ROOT=temporary), capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual("installer-downloaded" in result.stderr, not installed)
                if not installed:
                    self.assertLess(result.stderr.index("sudo -v"), result.stderr.index("installer-downloaded"))
                self.assertNotIn("wrapper-must-not-run", result.stderr)
                self.assertIn("Homebrew environment initialized.", result.stdout)

    def test_intel_macos_never_installs_or_upgrades_homebrew_yq(self):
        calls, _ = self.run_bootstrap("Darwin", "x86_64")
        self.assertNotIn("install --quiet yq", calls)
        self.assertFalse(any(call.startswith("upgrade") for call in calls))
        self.assertIn("standalone-yq-ready", calls)
        self.assertFalse(any(call.startswith("install ") for call in calls))

    def test_intel_macos_uses_system_baseline_instead_of_building_replacements(self):
        calls, result = self.run_bootstrap("Darwin", "x86_64", "git")
        self.assertFalse(any(call.startswith("install ") for call in calls))
        self.assertIn("Intel baseline ready", result.stdout)
        self.assertNotIn("install --quiet yq", calls)

    def test_other_platforms_retain_homebrew_yq_and_upgrade(self):
        for platform, arch in (("Darwin", "arm64"), ("Linux", "x86_64"), ("Linux", "aarch64")):
            with self.subTest(platform=platform, arch=arch):
                calls, _ = self.run_bootstrap(platform, arch)
                self.assertIn("install --quiet yq", calls)
                self.assertIn("upgrade --quiet", calls)
                self.assertLess(calls.index("install --quiet yq"), calls.index("standalone-yq-ready"))

    def test_homebrew_yq_failure_on_other_platforms_uses_fallback(self):
        calls, result = self.run_bootstrap("Darwin", "arm64", "yq")
        self.assertIn("standalone-yq-ready", calls)
        self.assertIn("install --quiet gawk", calls)
        self.assertIn("trying the standalone fallback", result.stderr)

    def test_background_profile_setup_preserves_content_and_unchanged_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            profile = root / ".zprofile"
            profile.write_text("# existing user configuration\nexport MY_SETTING=kept\n")
            environment = os.environ.copy()
            environment.update(HOME=temporary, TEST_ROOT=temporary)
            script = '''source "$1/functions.sh"
DARWIN=1
HOMEBREW_PATH="$TEST_ROOT/prefix with spaces"
func_persist_macos_brew_env
'''
            for run in range(2):
                subprocess.run(["/bin/bash", "-c", script, "test", str(REPO)], env=environment, check=True)
                if run == 0:
                    first_modified = profile.stat().st_mtime_ns
            self.assertEqual(profile.stat().st_mtime_ns, first_modified)
            self.assertIn("export MY_SETTING=kept", profile.read_text())
            self.assertEqual(profile.read_text().count("shellenv"), 1)

    def test_verified_mac_queue_skips_foreground_baseline_installs_and_upgrades(self):
        calls, _ = self.run_bootstrap("Darwin", "x86_64", packages_ready=True)
        self.assertFalse(any(call.startswith(("install ", "upgrade ")) for call in calls))

    def test_verified_mac_queue_flag_does_not_change_linux_installation(self):
        calls, _ = self.run_bootstrap("Linux", "x86_64", packages_ready=True)
        self.assertIn("install --quiet yq", calls)
        self.assertIn("upgrade --quiet", calls)


if __name__ == "__main__":
    unittest.main()

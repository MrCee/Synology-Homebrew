"""Isolated queue tests: no real Homebrew commands or LaunchAgents are run."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]


@unittest.skipIf(os.geteuid() == 0, "The macOS worker deliberately refuses root")
class BackgroundQueueTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="brew queue & test ")
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.repo = self.root / "repository"
        self.repo.mkdir()
        self.home = self.root / "home"
        self.home.mkdir()
        self.installed = self.root / "installed"
        self.installed.mkdir()
        self.processes = []
        for name in ("background-packages.sh", "macos-package-status.js"):
            shutil.copy(REPO / name, self.repo / name)
        (self.repo / "functions.sh").write_text('''func_initialize_env_vars() {
    DARWIN=1; HOMEBREW_PATH="$TEST_ROOT"; export DARWIN HOMEBREW_PATH
}
func_bootstrap_yq() { return 0; }
get_minimal_baseline() { echo 'yq git ruby'; }
''')
        self.executable("uname", "echo Darwin\n")
        self.executable("launchctl", '''printf "%s\\n" "$*" >> "$TEST_ROOT/launchctl-calls"
if [[ "$1" == bootout && "$2" == */com.mrcee.synology-homebrew.packages && -f "$TEST_ROOT/stop-worker-pid" ]]; then
    kill -TERM -- -"$(cat "$TEST_ROOT/stop-worker-pid")" 2>/dev/null || true
fi
''')
        self.executable("yq", '''[[ "$2" == . ]] && exit 0
printf '%s\n' "$TEST_PACKAGES"
''')
        self.executable("brew", '''case "$1" in
shellenv|--version) exit 0 ;;
list) [[ -f "$TEST_ROOT/installed/$3" ]]; exit $? ;;
install)
    package=$2
    echo "$package" >> "$TEST_ROOT/install-calls"
    printf '%s|%s|%s|%s\n' "$HOMEBREW_MAKE_JOBS" "$HOMEBREW_NO_ASK" "$HOMEBREW_NO_SUDO" "$HOMEBREW_NO_INSTALL_UPGRADE" >> "$TEST_ROOT/install-environment"
    while [[ -f "$TEST_ROOT/block-package" && "$(cat "$TEST_ROOT/block-package")" == "$package" ]]; do sleep 0.1; done
    if [[ -f "$TEST_ROOT/fail-package" && "$(cat "$TEST_ROOT/fail-package")" == "$package" ]]; then exit 1; fi
    touch "$TEST_ROOT/installed/$package"
    exit 0 ;;
*) exit 2 ;;
esac
''')
        self.environment = os.environ.copy()
        self.environment.update(
            HOME=str(self.home), TEST_ROOT=str(self.root), TEST_PACKAGES="alpha\nbeta",
            PATH=str(self.bin) + ":/usr/bin:/bin", SYNOBREW_BUILD_JOBS="2",
        )
        self.config = self.repo / "config.yaml"
        self.config.write_text("# immutable config snapshot\n")
        self.controller = self.repo / "background-packages.sh"

    def executable(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\n" + body)
        path.chmod(0o755)

    def command(self, *arguments, expect=0):
        result = subprocess.run(
            ["/bin/bash", str(self.controller), *map(str, arguments)],
            env=self.environment, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, expect, result.stdout + result.stderr)
        return result

    def prepare(self, paused=False):
        self.command("start", self.config, *(["--paused"] if paused else []))
        state = self.home / ".local/share/synology-homebrew/background"
        self.job = Path((state / "latest").read_text().strip())
        return self.job

    def worker(self):
        log = open(self.job / "test-worker.log", "a")
        process = subprocess.Popen(
            ["/bin/bash", str(self.job / "runner.sh"), "run"],
            env=self.environment, stdout=log, stderr=log, start_new_session=True,
        )
        log.close()
        self.processes.append(process)
        return process

    def wait_state(self, state, timeout=12):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if (self.job / "status").read_text().strip() == state:
                return
            time.sleep(0.05)
        self.fail("Expected state " + state + ": " + (self.job / "test-worker.log").read_text())

    def tearDown(self):
        (self.root / "block-package").unlink(missing_ok=True)
        for process in self.processes:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        self.temporary.cleanup()

    def test_snapshot_and_login_agents(self):
        self.prepare()
        self.assertEqual((self.job / "queue").read_text().splitlines(), ["git", "ruby", "alpha", "beta"])
        self.config.write_text("# changed later\n")
        self.assertEqual((self.job / "config.yaml").read_text(), "# immutable config snapshot\n")
        agents = list((self.home / "Library/LaunchAgents").glob("*.plist"))
        self.assertEqual(len(agents), 2)
        for path in agents:
            plist = plistlib.loads(path.read_bytes())
            self.assertTrue(plist["RunAtLoad"])
            self.assertNotIn("KeepAlive", plist)
            self.assertNotIn("StartInterval", plist)
            self.assertTrue(any(str(self.job) in item for item in plist["ProgramArguments"]))
        self.command("start", self.config, expect=1)

    def test_stale_lock_after_restart_skips_verified_completed_packages(self):
        self.prepare()
        (self.job / "status").write_text("running\n")
        (self.job / "completed").write_text("git\n")
        (self.installed / "git").touch()
        (self.job / "lock").mkdir()
        (self.job / "lock/pid").write_text("999999999\n")
        process = self.worker()
        self.wait_state("packages_ready")
        self.assertEqual(process.wait(timeout=3), 0)
        self.assertNotIn("git", (self.root / "install-calls").read_text().splitlines())
        self.assertEqual(len((self.job / "completed").read_text().splitlines()), 4)
        self.assertTrue(all(line == "2|1|1|1" for line in (self.root / "install-environment").read_text().splitlines()))

    def test_failed_package_does_not_skip_others_and_retries_automatically(self):
        self.prepare()
        (self.root / "fail-package").write_text("alpha")
        process = self.worker()
        self.wait_state("retry_wait")
        self.assertIn("beta", (self.job / "completed").read_text().splitlines())
        self.assertEqual((self.job / "failures").read_text().strip(), "alpha")
        (self.root / "fail-package").unlink()
        (self.job / "next-retry").write_text("0\n")
        self.wait_state("packages_ready")
        self.assertEqual(process.wait(timeout=3), 0)
        calls = (self.root / "install-calls").read_text().splitlines()
        self.assertEqual(calls.count("alpha"), 2)
        self.assertEqual(calls.count("git"), 1)

    def test_pause_after_current_package_then_resume(self):
        self.prepare()
        (self.root / "block-package").write_text("git")
        process = self.worker()
        self.wait_state("running")
        self.command("pause")
        (self.root / "block-package").unlink()
        self.wait_state("paused")
        self.assertEqual(process.wait(timeout=3), 0)
        self.command("resume")
        calls = (self.root / "launchctl-calls").read_text().splitlines()
        self.assertEqual(sum("bootout" in call and call.endswith(".status") for call in calls), 1)
        process = self.worker()
        self.wait_state("packages_ready")
        self.assertEqual(process.wait(timeout=3), 0)

    def test_duplicate_worker_does_not_start_parallel_install(self):
        self.prepare()
        (self.root / "block-package").write_text("git")
        first = self.worker()
        self.wait_state("running")
        second = self.worker()
        self.assertEqual(second.wait(timeout=3), 0)
        self.assertIsNone(first.poll())
        self.command("disable", expect=1)
        (self.root / "block-package").unlink()
        self.wait_state("packages_ready")
        first.wait(timeout=3)
        self.assertEqual((self.root / "install-calls").read_text().splitlines().count("git"), 1)

    def test_invalid_formula_is_rejected(self):
        self.environment["TEST_PACKAGES"] = "--malicious-option"
        self.command("start", self.config, expect=1)
        self.assertFalse((self.home / ".local/share/synology-homebrew/background/latest").exists())

    def test_disable_removes_agents_but_retains_queue_history(self):
        self.prepare()
        self.command("disable")
        self.assertEqual(list((self.home / "Library/LaunchAgents").glob("*.plist")), [])
        self.assertEqual((self.job / "status").read_text().strip(), "cancelled")
        self.assertTrue((self.job / "config.yaml").exists())

    def test_deferred_queue_does_not_compile_until_resumed(self):
        self.prepare(paused=True)
        self.assertEqual((self.job / "status").read_text().strip(), "paused")
        process = self.worker()
        self.assertEqual(process.wait(timeout=3), 0)
        self.assertFalse((self.root / "install-calls").exists())
        self.command("resume")
        process = self.worker()
        self.wait_state("packages_ready")
        self.assertEqual(process.wait(timeout=3), 0)

    def test_window_refresh_keeps_worker_snapshot_and_queue_unchanged(self):
        self.prepare()
        worker = (self.job / "runner.sh").read_bytes()
        queue = (self.job / "queue").read_bytes()
        (self.repo / "macos-package-status.js").write_text("// refreshed appearance\n")
        self.command("window")
        self.assertEqual((self.job / "status-window.js").read_text(), "// refreshed appearance\n")
        self.assertEqual((self.job / "runner.sh").read_bytes(), worker)
        self.assertEqual((self.job / "queue").read_bytes(), queue)

    def test_preexisting_formulas_are_counted_and_never_reinstalled(self):
        self.environment["TEST_PACKAGES"] = "alpha\nbeta\ncmake"
        (self.installed / "cmake").touch()
        (self.installed / "git").touch()
        (self.installed / "alpha").touch()
        self.prepare(paused=True)
        self.assertEqual((self.job / "completed").read_text().splitlines(), ["git", "alpha", "cmake"])
        # Also detect packages installed after queue creation.
        (self.installed / "ruby").touch()
        self.command("resume")
        process = self.worker()
        self.wait_state("packages_ready")
        self.assertEqual(process.wait(timeout=3), 0)
        self.assertEqual((self.root / "install-calls").read_text().splitlines(), ["beta"])

    def test_stop_terminates_active_build_and_resumes_without_reinstalling_completed(self):
        self.prepare()
        (self.root / "block-package").write_text("ruby")
        process = self.worker()
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            calls = self.root / "install-calls"
            if calls.exists() and "ruby" in calls.read_text().splitlines():
                break
            time.sleep(0.05)
        else:
            self.fail("Worker did not reach blocked ruby build")
        (self.root / "stop-worker-pid").write_text(str(process.pid))
        queue = (self.job / "queue").read_bytes()
        self.command("stop")
        process.wait(timeout=3)
        self.assertEqual((self.job / "status").read_text().strip(), "paused")
        self.assertEqual((self.job / "completed").read_text().splitlines(), ["git"])
        self.assertFalse((self.installed / "ruby").exists())
        self.assertEqual((self.job / "queue").read_bytes(), queue)
        # A login must not restart a deliberately stopped queue.
        self.assertEqual(self.worker().wait(timeout=3), 0)
        (self.root / "stop-worker-pid").unlink()
        (self.root / "block-package").unlink()
        self.command("resume")
        process = self.worker()
        self.wait_state("packages_ready")
        self.assertEqual(process.wait(timeout=3), 0)
        calls = (self.root / "install-calls").read_text().splitlines()
        self.assertEqual(calls.count("git"), 1)
        self.assertEqual(calls.count("ruby"), 2)

    def test_removed_completed_formula_is_reinstalled(self):
        self.prepare()
        (self.job / "completed").write_text("git\n")
        process = self.worker()
        self.wait_state("packages_ready")
        process.wait(timeout=3)
        self.assertIn("git", (self.root / "install-calls").read_text().splitlines())
        self.assertEqual((self.job / "completed").read_text().splitlines().count("git"), 1)

    def test_restart_with_reused_worker_pid_is_not_treated_as_an_active_worker(self):
        self.prepare()
        (self.job / "status").write_text("running\n")
        (self.job / "lock").mkdir()
        result = subprocess.run(
            ["/bin/bash", "-c", 'echo "$$" > "$1/lock/pid"; exec /bin/bash "$1/runner.sh" run', "test", str(self.job)],
            env=self.environment, capture_output=True, text=True, timeout=12,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.job / "status").read_text().strip(), "packages_ready")

    def test_finish_verification_requires_matching_config_and_installed_packages(self):
        self.prepare()
        process = self.worker()
        self.wait_state("packages_ready")
        process.wait(timeout=3)
        self.command("verify", self.config)
        self.config.write_text("# modified config\n")
        self.command("verify", self.config, expect=1)
        self.config.write_text((self.job / "config.yaml").read_text())
        (self.installed / "git").unlink()
        self.command("verify", self.config, expect=1)

    def test_linux_cannot_start_the_macos_queue(self):
        self.executable("uname", "echo Linux\n")
        self.command("start", self.config, expect=1)
        self.assertFalse((self.home / "Library/LaunchAgents").exists())

    @unittest.skipUnless(sys.platform == "darwin", "Native AppKit render requires macOS")
    def test_native_window_render_and_timer_callbacks(self):
        self.prepare()
        image = self.root / "window.png"
        for arguments in (("--render", str(image), "--appearance", "light"), ("--render", str(image), "--appearance", "dark"), ("--self-test",)):
            result = subprocess.run(
                ["/usr/bin/osascript", "-l", "JavaScript", str(REPO / "macos-package-status.js"), str(self.job), *arguments],
                capture_output=True, text=True, timeout=12,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(image.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"))


if __name__ == "__main__":
    unittest.main()

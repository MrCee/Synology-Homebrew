#!/usr/bin/env python3
"""Install this repo's enabled formulas through a process-local no-build guard.

Does not run the shell/dotfiles, sudoers, pruning, or Neovim configuration setup.
"""
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import signal
import tempfile
import upstream_binaries


def run(arguments, **kwargs):
    """Keep interrupts/timeouts from leaving a package process running."""
    with subprocess.Popen(arguments, start_new_session=True, **kwargs) as child:
        try:
            return child.wait(timeout=300)
        except (KeyboardInterrupt, subprocess.TimeoutExpired):
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
            raise


def install_thefuck():
    # thefuck imports imp, removed in Python 3.12. Apple's CLT Python 3.9
    # works; keep its dependencies isolated and forbid all source distributions.
    python = "/usr/bin/python3"
    environment = Path.home() / ".local/share/synology-homebrew/thefuck-python39"
    subprocess.run([python, "-m", "venv", str(environment)], check=True)
    subprocess.run([str(environment / "bin/python"), "-m", "pip", "install",
                    "--only-binary=:all:", "thefuck==3.32", "setuptools<81"], check=True, timeout=180)
    command = environment / "bin/thefuck"
    subprocess.run([str(command), "--version"], check=True, timeout=30)
    link = Path("/usr/local/bin/thefuck")
    if os.path.lexists(link):
        if not (link.is_symlink() and link.resolve() == command):
            raise RuntimeError("Refusing to overwrite " + str(link))
    else:
        link.symlink_to(command)
    return "isolated Python wheels (Apple CLT Python 3.9)"


def main():
    if sys.version_info < (3, 12):
        sys.exit("Use Python 3.12+ for safe archive extraction, e.g. /usr/local/bin/python3.")
    if os.geteuid() == 0:
        sys.exit("Run as your normal Mac login user, not root.")
    if platform.system() != "Darwin" or platform.machine() != "x86_64":
        sys.exit("This installer currently targets Intel macOS only.")
    root = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location("audit", root / "audit-macos-bottles.py")
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    arguments = sys.argv[1:]
    plan = "--plan" in arguments
    arguments = [argument for argument in arguments if argument != "--plan"]
    if any(argument.startswith("-") for argument in arguments):
        sys.exit("Usage: install-macos-binaries.py [--plan] [formula ...]")
    packages = arguments or audit.configured_packages(root / "config.yaml")
    print("ℹ️ Detected macOS Intel: binary-only installation; source builds are blocked.", flush=True)
    if plan:
        print("Plan only: existing installs are reused first; routes below apply to missing packages.")
        for package in dict.fromkeys(packages):
            if package in upstream_binaries.MANIFEST:
                item = upstream_binaries.MANIFEST[package]
                print(package + ": SHA-256-verified binary — " + item["url"])
            elif package == "perl":
                print("perl: Apple system Perl; no Homebrew replacement")
            elif package == "thefuck":
                print("thefuck: isolated Python wheels only; no source distributions")
            else:
                print(package + ": guarded Homebrew bottle, including dependencies; fail if unavailable")
        return 0
    # Bypass the machine entry wrapper; this process invokes only the guarded
    # Ruby command for installation, never Homebrew's unguarded install command.
    brew = "/usr/local/bin/brew.before-synobrew"
    if not Path(brew).is_file():
        brew = "/usr/local/bin/brew"
    if not Path(brew).is_file():
        sys.exit("Homebrew must already be installed.")
    env = os.environ.copy()
    env.update(HOMEBREW_PREFIX="/usr/local", HOMEBREW_CELLAR="/usr/local/Cellar",
               HOMEBREW_REPOSITORY="/usr/local/Homebrew")
    env["PATH"] = str(root / "cmd") + os.pathsep + env["PATH"]
    for key in ("HOMEBREW_NO_AUTO_UPDATE", "HOMEBREW_NO_INSTALL_CLEANUP",
                "HOMEBREW_NO_INSTALL_UPGRADE", "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK",
                "HOMEBREW_NO_ASK"):
        env[key] = "1"
    cellar = subprocess.check_output([brew, "--cellar"], env=env, text=True).strip()
    if cellar != "/usr/local/Cellar":
        sys.exit("Unexpected Homebrew Cellar: " + cellar + "; refusing package changes.")
    subprocess.run([brew, "synobrew-binary-install", "--guard-self-test"], env=env, check=True)
    results = []
    for package in dict.fromkeys(packages):
        source_required = False
        base_package = package.rsplit("/", 1)[-1]
        green = "\033[0;32m" if sys.stdout.isatty() else ""
        normal = "\033[0m" if sys.stdout.isatty() else ""
        print("\n🛠️ " + green + base_package + normal + ": Installing...", flush=True)
        try:
            if run([brew, "list", "--versions", package], env=env,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0:
                status = "already installed (Homebrew)"
            elif package in upstream_binaries.MANIFEST:
                print("ℹ️ Using a verified Intel binary.", flush=True)
                status = upstream_binaries.install(package)
            elif package == "perl":
                subprocess.run(["/usr/bin/perl", "-e", "print qq(Perl $^V\\n)"], check=True)
                status = "Apple system Perl (5.34); no Homebrew replacement"
            elif package == "thefuck":
                status = install_thefuck()
            else:
                with tempfile.TemporaryDirectory(prefix="synobrew-check-") as temporary:
                    marker = Path(temporary) / "source-required"
                    package_env = dict(env, SYNOBREW_SOURCE_REQUIRED_FILE=str(marker))
                    code = run([brew, "synobrew-binary-install", package], env=package_env)
                    source_required = marker.exists()
                if code:
                    raise RuntimeError("No usable bottle or installation failed; compilation blocked")
                status = "installed (Homebrew bottle)"
            label = "Already installed" if status.startswith("already installed") else "Installed"
            print(green + "✅ " + base_package + normal + ": " + label + " (" + status + ")", flush=True)
            results.append({"package": package, "status": status})
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            print("❌ Error installing " + base_package + ": " + str(error), flush=True)
            results.append({"package": package, "status": "failed", "error": str(error),
                            "source_required": source_required})
        (root / "binary-install-results.json").write_text(json.dumps(results, indent=2) + "\n")
    report = root / "binary-install-results.json"
    report.write_text(json.dumps(results, indent=2) + "\n")
    return 1 if any(row["status"] == "failed" for row in results) else 0


if __name__ == "__main__":
    sys.exit(main())

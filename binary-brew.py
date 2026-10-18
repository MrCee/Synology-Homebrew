#!/usr/bin/env python3
"""Machine brew entry point: guard installs and refuse unguarded mutations."""
import os
from pathlib import Path
import re
import sys

REAL_BREW = "/usr/local/bin/brew.before-synobrew"
if not Path(REAL_BREW).is_file():
    REAL_BREW = "/usr/local/bin/brew"
ROOT = Path(__file__).resolve().parent


def dispatch(arguments):
    if arguments and arguments[0] == "install":
        packages = []
        for argument in arguments[1:]:
            if argument in {"--formula", "--formulae", "--quiet", "-q", "--yes", "-y", "--no-ask", "--"}:
                continue
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_@./+-]*", argument):
                raise ValueError("Binary-only brew refuses this install option: " + argument)
            token = argument.rsplit("/", 1)[-1].lower()
            if token.startswith(("avast", "xournal")):
                raise ValueError("Installation permanently blocked by your policy: " + argument)
            packages.append(argument)
        if not packages:
            raise ValueError("Usage: brew install <formula> ...")
        return [sys.executable, str(ROOT / "install-macos-binaries.py"), *packages]
    if arguments and arguments[0] in {"upgrade", "reinstall", "bundle", "postinstall", "post-install", "test"}:
        raise ValueError("Binary-only brew blocks " + arguments[0] +
                         ". Use brew install <formula> for guarded installs; existing versions are reused.")
    return [REAL_BREW, *arguments]


if __name__ == "__main__":
    # Avoid inherited shellenv values from an alternate Homebrew entry/prefix.
    os.environ["HOMEBREW_PREFIX"] = "/usr/local"
    os.environ["HOMEBREW_CELLAR"] = "/usr/local/Cellar"
    os.environ["HOMEBREW_REPOSITORY"] = "/usr/local/Homebrew"
    try:
        command = dispatch(sys.argv[1:])
    except ValueError as error:
        sys.exit(str(error))
    os.execv(command[0], command)

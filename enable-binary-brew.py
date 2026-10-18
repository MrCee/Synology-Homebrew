#!/usr/bin/env python3
"""Install the machine entry guard, preserving the original brew symlink."""
import os
from pathlib import Path
import shlex

root = Path(__file__).resolve().parent
entry = Path("/usr/local/bin/brew")
backup = Path("/usr/local/bin/brew.before-synobrew")
marker = "# Synology-Homebrew binary-only entry"
if entry.is_symlink() and entry.resolve() == Path("/usr/local/Homebrew/bin/brew"):
    if os.path.lexists(backup):
        raise SystemExit("Backup already exists; refusing to overwrite it.")
    entry.rename(backup)
elif entry.is_file() and marker in entry.read_text():
    pass
else:
    raise SystemExit("Unexpected brew entry; refusing to replace it.")
temporary = entry.with_name("brew.synobrew-tmp")
temporary.write_text("#!/bin/bash\n" + marker + "\nexec /usr/local/bin/python3 " +
                     shlex.quote(str(root / "binary-brew.py")) + ' "$@"\n')
temporary.chmod(0o755)
temporary.replace(entry)
print("Binary-only brew enabled. Original entry preserved at " + str(backup))

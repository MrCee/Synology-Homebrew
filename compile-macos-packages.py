#!/usr/bin/env python3
"""Explicit last resort: try binaries, then save only unbottled work paused."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def source_failures(results):
    return [row["package"] for row in results
            if row["status"] == "failed" and row.get("source_required") is True]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-source-builds", action="store_true", required=True,
                        help="Explicitly permit source builds for these formulae and dependencies")
    parser.add_argument("packages", nargs="+")
    arguments = parser.parse_args()
    if any(not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_@./+-]*", p) or ".." in p for p in arguments.packages):
        parser.error("Provide formula names, not options or paths.")
    root = Path(__file__).resolve().parent
    report = root / "binary-install-results.json"
    # Remove stale results; never start work based on a previous failed run.
    report.unlink(missing_ok=True)
    result = subprocess.run([sys.executable, str(root / "install-macos-binaries.py"), *arguments.packages])
    if not report.exists() or result.returncode not in (0, 1):
        sys.exit("Binary preflight did not complete; no compilation queue created.")
    rows = json.loads(report.read_text())
    if {r["package"] for r in rows} != set(arguments.packages):
        sys.exit("Incomplete binary preflight; no compilation queue created.")
    missing = source_failures(rows)
    if not missing:
        print("No confirmed missing bottles. No compilation queue created.")
        return result.returncode
    print("Last resort, selected formulae only: " + ", ".join(missing), flush=True)
    print("The progress window opens PAUSED. Resume starts compilation. Completed formulae are reused; the current interrupted formula may restart.", flush=True)
    with tempfile.TemporaryDirectory(prefix="synobrew-fallback-") as temporary:
        config = Path(temporary) / "config.yaml"
        config.write_text(json.dumps({"packages": {p: {"action": "install"} for p in missing}}))
        return subprocess.run(["/bin/bash", str(root / "background-packages.sh"), "start",
                               str(config), "--paused", "--allow-source-builds"]).returncode


if __name__ == "__main__":
    sys.exit(main())

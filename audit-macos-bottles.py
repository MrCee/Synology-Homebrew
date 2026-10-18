#!/usr/bin/env python3
"""Inspect current formula metadata without installing or invoking Homebrew.

This is a planning report, not an installation/compatibility guarantee.
Uses only the Python standard library and the public Homebrew formula API.
"""
import concurrent.futures
import json
import platform
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path


def configured_packages(path):
    # Deliberately accept only this repository's simple package/action structure.
    # Reject unfamiliar YAML rather than silently overlooking requested packages.
    result = []
    package = None
    in_packages = False
    for line in path.read_text().splitlines():
        if line == "packages:":
            in_packages = True
            continue
        if not in_packages or not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line.startswith(" "):
            break
        match = re.fullmatch(r"  ([A-Za-z0-9_@./+-]+):", line)
        if match:
            if package is not None:
                raise ValueError("Missing action for " + package)
            package = match.group(1)
        elif line.startswith("    action:"):
            action = line.split(":", 1)[1].strip()
            if package is None or action not in {"install", "skip"}:
                raise ValueError("Unsupported package/action structure: " + line)
            if action == "install":
                result.append(package)
            package = None
        elif not line.startswith("    "):
            raise ValueError("Unsupported package structure: " + line)
    if not in_packages or package is not None:
        raise ValueError("Missing packages section or package action")
    return result


def inspect(name):
    if "/" in name:
        return name, "REVIEW TAP", "third-party metadata must be checked separately"
    url = "https://formulae.brew.sh/api/formula/" + name + ".json"
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            formula = json.load(response)
        tags = sorted(formula.get("bottle", {}).get("stable", {}).get("files", {}))
        intel_tags = [tag for tag in tags if tag == "all" or re.fullmatch(
            r"(?:tahoe|sequoia|sonoma|ventura|monterey|big_sur|catalina|mojave|high_sierra)", tag)]
        status = "CANDIDATE" if intel_tags else "NO INTEL BOTTLE"
        if formula.get("disabled"):
            status = "DISABLED"
        return name, status, ", ".join(intel_tags) or "none in current stable metadata"
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return name, "REVIEW NAME", "API name not found; may be an alias or removed formula"
        return name, "ERROR", str(error)
    except (OSError, ValueError, urllib.error.URLError) as error:
        return name, "ERROR", str(error)


def main():
    if platform.system() != "Darwin" or platform.machine() != "x86_64":
        sys.exit("This audit currently targets Intel macOS only.")
    baseline = "git yq ruby python3 coreutils findutils gnu-sed grep gawk".split()
    packages = sys.argv[1:] or baseline + configured_packages(Path(__file__).with_name("config.yaml"))
    packages = list(dict.fromkeys(packages))
    print("Intel macOS bottle planning report — current Homebrew metadata")
    print("CANDIDATE means metadata exists, not that installation is verified.")
    print("Dependencies, relocation, OS compatibility and downloads still need validation.\n")
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        rows = list(pool.map(inspect, packages))
    for name, status, detail in rows:
        print("{:<35} {:<18} {}".format(name, status, detail))
    return 1 if any(status == "ERROR" for _, status, _ in rows) else 0


if __name__ == "__main__":
    sys.exit(main())

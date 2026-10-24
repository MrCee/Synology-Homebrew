"""Pinned Intel release installation; no source build commands are used."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent
MANIFEST = json.loads((ROOT / "upstream-binaries.json").read_text())
STORE = Path.home() / ".local/share/synology-homebrew/binaries"
BIN = Path("/usr/local/bin")


def install(package):
    item = MANIFEST[package]
    destination = STORE / (package.rsplit("/", 1)[-1] + "-" + item["version"])
    # Refuse unrelated existing commands, including broken symlinks.
    for command in item["executables"]:
        link = BIN / command
        if os.path.lexists(link) and not (link.is_symlink() and link.resolve().is_relative_to(STORE.resolve())):
            raise RuntimeError("Refusing to replace existing command: " + str(link))
    STORE.mkdir(parents=True, exist_ok=True)
    if not destination.exists():
        with tempfile.TemporaryDirectory(dir=STORE) as temporary:
            temporary = Path(temporary)
            archive = temporary / "download"
            print("📦 Downloading pinned Intel binary: " + package, flush=True)
            with urllib.request.urlopen(item["url"], timeout=120) as response, archive.open("wb") as output:
                shutil.copyfileobj(response, output)
            if hashlib.sha256(archive.read_bytes()).hexdigest() != item["sha256"]:
                raise RuntimeError("SHA256 mismatch: " + package)
            stage = temporary / "contents"
            stage.mkdir()
            if item.get("raw"):
                shutil.copy2(archive, stage / next(iter(item["executables"].values())))
            elif item.get("format") == "conda":
                # This eza package is self-contained; its only dependency is
                # macOS >=11.0. No conda environment or package manager needed.
                with zipfile.ZipFile(archive) as container:
                    payload = next(n for n in container.namelist() if n.startswith("pkg-") and n.endswith(".tar.zst"))
                    compressed = temporary / "payload.tar.zst"
                    compressed.write_bytes(container.read(payload))
                uncompressed = temporary / "payload.tar"
                with uncompressed.open("wb") as output:
                    subprocess.run(["/usr/local/bin/zstd", "-dc", str(compressed)], stdout=output, check=True)
                with tarfile.open(uncompressed) as tar:
                    tar.extractall(stage, filter="data")
            else:
                with tarfile.open(archive, "r:gz") as tar:
                    # Python's data filter refuses traversal and escaping links.
                    tar.extractall(stage, filter="data")
            for relative in item["executables"].values():
                executable = stage / relative
                if not executable.is_file():
                    raise RuntimeError("Missing release executable: " + str(executable))
                executable.chmod(executable.stat().st_mode | 0o755)
            stage.rename(destination)
    for command, relative in item["executables"].items():
        link = BIN / command
        if link.is_symlink():
            link.unlink()
        link.symlink_to(destination / relative)
    executable = next(iter(item["executables"]))
    subprocess.run([str(BIN / executable), "--version"], check=True, timeout=30)
    return "upstream binary " + item["version"]

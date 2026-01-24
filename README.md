# Synology-Homebrew

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/MrCee/Synology-Homebrew/pulls)
[![Last Commit](https://img.shields.io/github/last-commit/MrCee/Synology-Homebrew)](https://github.com/MrCee/Synology-Homebrew/commits)
[![Platform: DSM 7.2+](https://img.shields.io/badge/Platform-DSM%207.2%2B-1C1C1C)](https://www.synology.com/en-global/dsm)
[![macOS Supported](https://img.shields.io/badge/macOS-Supported-lightgrey)](https://support.apple.com/macos)
[![Arch: ARM64 & x86_64](https://img.shields.io/badge/Arch-ARM64%20%7C%20x86__64-1793D1)](https://en.wikipedia.org/wiki/X86-64)

---

## 🚀 Overview

**Synology-Homebrew** provides a safe, repeatable way to install and manage Homebrew on **Synology DSM 7.2+** and **macOS**, with two modes:

- **Minimal**: a clean base install of Homebrew + essentials  
- **Advanced**: drive everything from a `config.yaml` (packages, plugins, aliases)

It respects your Synology environment, avoids overwriting system packages, and includes a full uninstall path.

> ℹ️ For supported platforms, architectures, and DSM version notes, see  
> **[Compatibility & Platform Support](#-compatibility--platform-support)**.

---

## 🔥 What’s New (Minimal mode fixes)

Thanks to user reports, the installer has been updated to improve correctness and safety:

- **Minimal ≠ YAML**  
  Minimal no longer touches `config.yaml`. YAML parsing now only happens in **Advanced** mode.

- **Safer pruning in Minimal mode**  
  After a Minimal run, the script can **optionally prune** your system back to a minimal set by **only offering to uninstall leaf formulas** (things you explicitly installed).  
  On macOS and Synology, baselines differ (see below).

---

## ⚙️ Installation Guide

### 🚀 Quick Start (Synology NAS)

1. SSH into DSM 7.2+  
2. Clone & run the installer:

```zsh
git clone https://github.com/MrCee/Synology-Homebrew.git ~/Synology-Homebrew && \
~/Synology-Homebrew/install-synology-homebrew.sh
```

Choose **1 = Minimal** or **2 = Advanced** when prompted.

---

### 💻 Quick Start (macOS)

```zsh
git clone https://github.com/MrCee/Synology-Homebrew.git ~/Synology-Homebrew && \
~/Synology-Homebrew/install-synology-homebrew.sh
```

- On Intel Macs, Homebrew installs to `/usr/local`  
- On Apple Silicon Macs, Homebrew installs to `/opt/homebrew`  
- The installer adds `brew shellenv` to your `~/.zprofile` so Homebrew is always on your PATH  

---

## 🧼 Option 1: Minimal Install (Clean & Lightweight)

- Installs **Homebrew + essentials** only (platform-specific baseline)  
- **Ignores `config.yaml` entirely**  
- Offers a **prune** prompt at the end (optional) to remove extras you installed previously  

### Minimal baselines

- **Synology/Linux baseline**  
  `binutils glibc gcc git ruby python3 zsh yq`

- **macOS baseline**  
  `git yq ruby python3 coreutils findutils gnu-sed grep gawk`  

---

## ⚡ Option 2: Advanced Install (Fully Loaded)

- Parses **`config.yaml`** and applies your declared actions:  
  - `install` → install package/plugin  
  - `uninstall` → remove it  
  - `skip` → do nothing  
- Adds aliases and `eval` lines to your `~/.zshrc`, but only for packages you’ve chosen to keep  
- Invokes optional Neovim bootstrap and Zsh configuration helpers when flagged in YAML  

---

## 🍃 Minimal “Prune” (What it does and doesn’t do)

At the end of **Minimal mode**:

- The script computes **extras** by comparing your **explicitly installed leaf formulas** (`brew leaves`) with the **minimal baseline** for your platform.  
- It **offers** to uninstall those extras.  
- It **does not** remove dependencies required by remaining formulas or by Homebrew itself.  

This keeps pruning **safe** and predictable.

---

## 🧱 Synology Notes (DSM 7.2+)

- The installer avoids overwriting Synology system files  
- Homebrew is installed in a self-contained prefix  
- `~/.profile` is updated to include Homebrew’s bin directories  
- Optional post-boot tasks can be used to re-bind `/home` and correct permissions  

---

## 🔧 Compatibility & Platform Support

This project is **fully validated on DSM 7.2+** and **supported macOS versions**.

We have made **best-effort accommodations for DSM 7.1**, however support on DSM 7.1 is **inherently limited by platform and upstream constraints**.

### ✅ Supported platforms

- **Synology DSM 7.2+**
  - `x86_64` (Intel 64-bit)
  - `aarch64 / arm64` (ARM64, model-dependent)
- **macOS**
  - Intel (`x86_64`)
  - Apple Silicon (`arm64`)

### ⚠️ DSM 7.1 (limited support)

What works:

- Installer validation and preflight checks  
- **Minimal mode** on compatible architectures  
- No Synology system packages are overwritten  

What does **not** work or is **not guaranteed**:

- ❌ **32-bit ARM systems** (`armv7l`, `armv6l`, `armhf`)
- ❌ Any architecture unsupported by Homebrew
- ❌ Guaranteed bottle availability or build success
- ❌ Full **Advanced mode parity** with DSM 7.2+
- ❌ Fixes for Homebrew upstream limitations

> **Important:**  
> Synology NAS devices using **32-bit ARM CPUs** cannot run Homebrew at all.  
> This is a **Homebrew limitation**, not a bug in this installer.

### 🚫 Unsupported platforms (hard stop)

- armv7 / armv6 / armhf  
- i386 / i686  
- Any non-64-bit CPU architecture  
- Operating systems unsupported by Homebrew  

---

## 🍎 macOS Notes

- Homebrew installs to `/opt/homebrew` on Apple Silicon  
- Homebrew installs to `/usr/local` on Intel  
- The installer updates your `~/.zprofile` with `brew shellenv`  
- Since macOS already includes zsh, the script does not install it  

---

## 🛡️ Security & Safety

- No hidden network calls beyond Homebrew itself  
- No credentials or sudo passwords are logged  
- Sudoers fragments are created and removed automatically  
- Full uninstall path is included  
- 100% open-source and auditable  

---

## 🧩 Troubleshooting

### “No space left on device” unpacking bottles (DSM)

On Synology DSM, the system `/tmp` directory resides on the small system volume.  
Large Homebrew bottles or build stages can exhaust this space on older setups.

The installer accounts for this internally so installs complete reliably.

### Minimal tried to validate YAML

Fixed. Minimal no longer touches `config.yaml`. YAML parsing only happens in **Advanced** mode.

### Minimal “prune” isn’t removing enough

Prune only targets **leaf formulas** (`brew leaves`).  
To remove dependencies, uninstall their leaf dependents first.

### Git messages during install

The installer prints the current git commit hash and branch for traceability.  
This output is informational only.

---

## 📥 Install Git (DSM) if missing

```bash
curl -sSL https://raw.githubusercontent.com/MrCee/Synology-Git/refs/heads/main/install-synology-git.sh | bash
```

---

## 🤝 Contributing

- Found a bug? Open an issue with:
  - Synology model and DSM version  
  - `uname -m` (architecture)  
  - Minimal vs Advanced mode  
  - Relevant log output and commit hash  

PRs are welcome — especially for portability, documentation, and edge-case handling.

---

## ⚖️ License

This project is licensed under the [MIT License](./LICENSE).

---

## ☕ Buy Me a Coffee

<p align="left">
  <a href="https://www.buymeacoffee.com/MrCee" target="_blank" rel="noopener">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-violet.png" width="200" alt="Buy Me A Coffee">
  </a>
</p>

If this script saved your bacon, rescued your dotfiles, or spared you from another SSH debugging spiral — legend.  
Buy me a coffee (flat white, long black, or whatever keeps the terminal open) and I’ll keep shipping fixes, features, and fewer headaches.


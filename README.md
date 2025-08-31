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

---

## 🔥 What’s New (Minimal mode fixes)

Thanks to user reports (e.g., large bottles like `binutils` or `gcc` extracting into `/`, and YAML being parsed in Minimal mode), the installer has been updated:

- **Minimal ≠ YAML**  
  Minimal no longer touches `config.yaml`. YAML parsing now only happens in **Advanced** mode.

- **Bottles extract off the tiny root volume (DSM)**  
  On Synology, Homebrew’s temp is forced to **`$HOME/tmp`**, preventing large bottles from filling `/tmp` on `md0`.  
  The script also sets `TMPDIR=$HOME/tmp` during install.

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

> On DSM, bottle extraction is done under `$HOME/tmp` to avoid filling the small `/` volume.

---

## ⚡ Option 2: Advanced Install (Fully Loaded)

- Parses **`config.yaml`** and applies your declared actions:  
  - `install` → install package/plugin  
  - `uninstall` → remove it  
  - `skip` → do nothing  
- Adds aliases and `eval` lines to your `~/.zshrc`, but only for packages you’ve chosen to keep  
- Invokes optional Neovim bootstrap and Zsh configuration helpers when flagged in YAML  

**File location:**
```zsh
~/Synology-Homebrew/config.yaml
```

**Open it with:**
```zsh
nvim ~/Synology-Homebrew/config.yaml
# or
nano ~/Synology-Homebrew/config.yaml
```

**Example (excerpt):**
```yaml
packages:
  neovim:
    action: install
    aliases:
      vim: "nvim"
    eval: []

  bat:
    action: install
    aliases:
      cat: "bat --paging=never"
    eval: []

plugins:
  powerlevel10k:
    action: install
    url: "https://github.com/romkatv/powerlevel10k"
    directory: "~/.oh-my-zsh/custom/themes/powerlevel10k"
    aliases: []
    eval: []

  kickstart.nvim:
    action: install
    url: "https://github.com/nvim-lua/kickstart.nvim"
    directory: "~/.config/nvim-kickstart"
    aliases:
      nvim: 'NVIM_APPNAME="nvim-kickstart" nvim'
    eval: []
```

---

## 🍃 Minimal “Prune” (What it does and doesn’t do)

At the end of **Minimal mode**:

- The script computes **extras** by comparing your **explicitly installed leaf formulas** (`brew leaves`) with the **minimal baseline** for your platform.  
- It **offers** to uninstall those extras.  
- It **does not** remove dependencies required by remaining formulas or by Homebrew itself.  

This keeps pruning **safe** and predictable.

---

## 🧱 Synology Notes (DSM 7.2+)

- **Homebrew temp** is set to **`$HOME/tmp`** during install so big bottles don’t fill `/`:  
  - `HOMEBREW_TEMP=$HOME/tmp`  
  - `TMPDIR=$HOMEBREW_TEMP`  
- After installation, `~/.profile` is updated to include Homebrew’s bin directories.  
- A post-boot Task Scheduler job can re-bind `/home` and fix permissions (see snippet below).

**Suggested boot task (User-defined Script):**
```bash
#!/bin/bash
[[ ! -d /home ]] && sudo mkdir /home
if ! grep -qs ' /home ' /proc/mounts; then
  sudo mount -o bind "$(readlink -f /var/services/homes)" /home
fi
sudo chown root:root /home && sudo chmod 775 /home
if [[ -d /home/linuxbrew ]]; then
  sudo chown root:root /home/linuxbrew && sudo chmod 775 /home/linuxbrew
fi
```

---

## 🍎 macOS Notes

- Homebrew installs to `/opt/homebrew` on Apple Silicon, and `/usr/local` on Intel  
- The installer updates your `~/.zprofile` with `brew shellenv`  
- Since macOS already includes zsh, the script does not install it  
- **oh-my-zsh** is installed by default (you can comment that block out if you don’t want it)  

---

## 🧪 Neovim (optional)

You can bootstrap Neovim via **Advanced** mode and/or use `kickstart.nvim`.  
Switch profiles with `NVIM_APPNAME`:

```zsh
NVIM_APPNAME="nvim-kickstart" nvim
```

Inside Neovim, run:
```vim
:checkhealth
```

<img src="screenshots/SCR-neovim-plugins-updated.png" width="800">

---

## 🖌️ Customize Your Zsh

Your shell environment comes preloaded with:

- `zsh` + `oh-my-zsh`  
- The `powerlevel10k` theme  
- Helpful plugins (such as autosuggestions and syntax highlighting)  
- Useful command aliases (`ll`, `vim → nvim`, `cat → bat`, `cd → zoxide`, `ls → eza`)

<img src="screenshots/SCR-iTerm2.png" width="800">

---

## 📦 Installed Packages (Advanced)

When you select **Advanced Install**, the script installs everything defined in `config.yaml`.  
Below is the full curated list — collapsed for readability, but fully indexed (search engines and GitHub search can still see it).

<details>
<summary>📋 Click to expand full package list</summary>

| Package | Description | Dependency |
|---------|-------------|------------|
| [brew](https://brew.sh) | Homebrew - The Missing Package Manager now for macOS & Linux. | Essential for: Synology-Homebrew |
| [git](https://git-scm.com) | Latest version replaces Synology Package Centre version. | Essential for: Synology-Homebrew |
| [ruby](https://www.ruby-lang.org) | Latest version replaces Synology Package Centre version. | Essential for: Synology-Homebrew |
| [zsh](https://www.zsh.org) | UNIX shell (command interpreter). | Essential for: Synology-Homebrew |
| [python3 / pip3](https://www.python.org) | Latest version installed. | Essential for: Synology-Homebrew |
| [glibc](https://www.gnu.org/software/libc) | The GNU C Library - Core libraries for the GNU system. | Essential for: Synology-Homebrew |
| [gcc](https://gcc.gnu.org) | GNU compiler collection. | Essential for: Synology-Homebrew |
| [oh-my-zsh](https://ohmyz.sh) | Community-driven framework for managing Zsh configuration. | Essential for: Synology-Homebrew, zsh |
| [jq](https://jqlang.github.io/jq) | Lightweight and flexible command-line JSON processor. | Essential for: Synology-Homebrew |
| [make](https://www.gnu.org/software/make) | Utility for directing compilation. | Essential for: neovim plugins |
| [node](https://nodejs.org) | JavaScript runtime environment. | Essential for: neovim |
| [neovim](https://neovim.io) | Hyperextensible Vim-based text editor. | Recommended for: Synology |
| [powerlevel10k](https://github.com/romkatv/powerlevel10k) | A theme for zsh. | Recommended for: oh-my-zsh |
| [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) | A plugin for zsh. | Recommended for: oh-my-zsh |
| [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) | A plugin for zsh. | Recommended for: oh-my-zsh |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | Recursive regex directory search tool. | Essential for: neovim, telescope, fzf |
| [fd](https://github.com/sharkdp/fd) | User-friendly alternative to `find`. | Essential for: neovim, telescope |
| [fzf](https://github.com/junegunn/fzf) | A command-line fuzzy finder. | Essential for: neovim, telescope |
| [fzf-git.sh](https://github.com/junegunn/fzf-git.sh) | Bash and zsh key bindings for Git objects. | Recommended for: neovim, telescope, fzf |
| [bat](https://github.com/sharkdp/bat) | A `cat` clone with syntax highlighting and Git integration. | Recommended for: zsh, neovim |
| [git-delta](https://github.com/dandavison/delta) | Syntax highlighting for diffs using Levenshtein algorithm. | Recommended for: neovim |
| [eza](https://github.com/eza-community/eza.git) | A modern replacement for `ls`. | Recommended for: zsh, neovim |
| [tldr](https://github.com/tldr-pages/tldr) | Simplified help pages for command-line tools. | Recommended for: neovim |
| [thefuck](https://github.com/nvbn/thefuck) | Corrects previous console command errors. | Recommended for: zsh |
| [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim) | A starting point for Neovim. | Optional for: neovim |
| [perl](https://www.perl.org) | Feature-rich programming language. | Essential for: stow |
| [stow](https://www.gnu.org/software/stow) | GNU Stow: Manage symlinks for dotfiles. | Optional |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | Smarter `cd` command, inspired by `z` and `autojump`. | Recommended for: zsh |
| [lazygit](https://github.com/jesseduffield/lazygit) | Terminal UI for Git commands. | Recommended for: zsh, neovim |

</details>

---

## 🛡️ Security & Safety

- No hidden network calls beyond Homebrew itself  
- No credentials or sudo passwords are logged  
- Sudoers fragments are created + removed automatically at the end of a run  
- Full uninstall path is included  
- 100% open-source and auditable  

---

## 🧩 Troubleshooting

### “No space left on device” unpacking bottles (DSM)  
This happens because DSM’s `/tmp` lives on the small `md0` volume. The installer now sets:

```zsh
export HOMEBREW_TEMP=$HOME/tmp
export TMPDIR=$HOMEBREW_TEMP
```

### Minimal tried to validate YAML  
Fixed. Minimal no longer touches `config.yaml`. YAML parsing only happens in **Advanced**.

### Minimal “prune” isn’t removing enough  
Prune only targets **leaf formulas** (`brew leaves`). To remove dependencies, uninstall their leaf dependents first.

### Git messages during install  
The installer shows the current git commit hash and whether your branch is up to date with `origin`. This is informational only.

---

## 📥 Install Git (DSM) if missing

```bash
curl -sSL https://raw.githubusercontent.com/MrCee/Synology-Git/refs/heads/main/install-synology-git.sh | bash
```

---

## 🤝 Contributing

- Found a bug? Open an issue with:  
  - Synology model, DSM version  
  - `uname -m` (arch), minimal vs advanced  
  - Log excerpt and Git commit hash printed by the script  
- PRs welcome — especially for prune logic, docs, and portability  

---

## ⚖️ License

This project is licensed under the [MIT License](./LICENSE).

---

## 🙏 Credits

- The Homebrew team and community  
- @ogerardin, @AppleBoiy, @josean-dev, @tjdevries  
- Everyone filing issues and PRs — thank you!  


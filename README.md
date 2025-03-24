# Synology-Homebrew

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/MrCee/Synology-Homebrew/pulls)
[![Last Commit](https://img.shields.io/github/last-commit/MrCee/Synology-Homebrew)](https://github.com/MrCee/Synology-Homebrew/commits)
[![Platform: DSM 7.2+](https://img.shields.io/badge/Platform-DSM%207.2%2B-1C1C1C)](https://www.synology.com/en-global/dsm)
[![macOS Supported](https://img.shields.io/badge/macOS-Supported-lightgrey)](https://support.apple.com/macos)
[![Arch: ARM64 & x86_64](https://img.shields.io/badge/Arch-ARM64%20%7C%20x86__64-1793D1)](https://en.wikipedia.org/wiki/X86-64)


---

## 🚀 Overview

Welcome to **Synology-Homebrew** – the easiest and safest way to get Homebrew running on your Synology NAS or macOS device.

This installer:

- Ensures Homebrew is correctly mounted on DSM 7.2+
- Avoids overwriting or deleting existing Synology packages
- Comes with a full uninstall option
- Mirrors your terminal setup on macOS (Intel & Apple Silicon)

📦 Whether you're setting up Neovim, configuring plugins with `config.yaml`, or building a powerful shell with zsh and oh-my-zsh, this repo helps you do it cleanly and consistently.

---

## 💡 Why Homebrew on Synology or macOS?

Homebrew, the package manager for macOS and Linux, unlocks a vast ecosystem of open-source tools. On Synology NAS, this means:

- Installing modern CLI tools without waiting for package updates
- Using advanced dev environments on low-power NAS devices
- Sharing dotfiles/config across macOS & NAS seamlessly

---

## 🔧 Key Features

- **Installation Modes**: Minimal or Advanced setups based on your needs.
- **Synology Integration**: Coexists with Synology packages without removing or breaking system services.
- **Cross-Platform**: Use the same config on Synology NAS, Intel Macs, and Apple Silicon.
- **Safe Uninstall**: Revert your system to its original state using the provided script.
- **Zsh & Theme Setup**: Comes with oh-my-zsh, powerlevel10k, and aliases for a powerful terminal experience.
- **Neovim Ready**: Optional full Neovim configuration via kickstart.nvim or your custom dotfiles.

---

## 🛡️ Security & Trust


This script is designed with safety in mind:

- **No hidden network calls** to unknown sources.
- **Does not capture credentials** or sudo passwords.
- **Respects your Synology environment** – does not remove or conflict with built-in packages.
- **Full uninstall script** included for rollback.
- All code is open-source and auditable. [Submit issues](https://github.com/MrCee/Synology-Homebrew/issues) or PRs to improve security.

---

## ⚙️ Installation Guide

### 🚀 Quick Start (Synology NAS)

1. **SSH into your Synology NAS** (DSM 7.2 or newer).
2. **Run the following command** to clone the repo and launch the installer:

```bash
git clone https://github.com/MrCee/Synology-Homebrew.git ~/Synology-Homebrew && \
~/Synology-Homebrew/install-synology-homebrew.sh
```

3. **Choose your install type** when prompted:

---

### 🧼 Option 1: Minimal Install (Clean & Lightweight)

- Installs Homebrew and core dependencies only
- Ignores all additional packages in `config.yaml`
- Use this for a bare setup or as a base to build on later

You can rerun the installer at any time to switch to Advanced mode or uninstall.

---

### ⚡ Option 2: Advanced Install (Fully Loaded)

- Installs everything defined in `config.yaml`
- Includes Neovim, CLI tools, shell enhancements, aliases, plugins, and themes
- Recommended for a full developer-ready setup

---

### 📦 Packages Always Installed

Regardless of install type, the following **essential packages** are always included to support Homebrew functionality on Synology:

- `git`, `ruby`, `glibc`, `gcc`, `python3`, `yq`, `zsh`, `oh-my-zsh`


---

## 📋 Prerequisites & Preflight

### 🧾 Synology NAS Requirements

Make sure the following are configured:

- ✅ Synology NAS with **DSM 7.2 or later**
- ✅ **SSH access** enabled (`Control Panel > Terminal & SNMP > Enable SSH service`)
- ✅ **User home directories** enabled (`Control Panel > User > Advanced > Enable user home service`)
- ✅ Set up **scheduled task** (see below) to remount Homebrew after reboot

---

### 📥 Install Git via CLI (if needed)

If Git is not already installed, run this command to install a minimal version. This will later be replaced by Homebrew’s Git:

```bash
curl -sSL https://raw.githubusercontent.com/MrCee/Synology-Git/refs/heads/main/install-synology-git.sh | bash
```

---

### 💻 macOS Terminal Environment (Optional but Recommended)

For macOS users planning to sync terminal config with Synology:

- Use **iTerm2** instead of the default Terminal.app
- Install a **Nerd Font** (e.g., [nerdfonts.com](https://www.nerdfonts.com/font-downloads))
- Configure a color profile (e.g. coolnight.itermcolors)

Check the [iTerm2 Configuration Guide](https://github.com/MrCee/Synology-Homebrew/wiki/iTerm2-Configuration) for setup instructions.

---

### 🔁 Persist Homebrew After Reboot (Synology)

To automatically mount the Homebrew directory after a NAS reboot:

1. Go to **Control Panel > Task Scheduler**
2. Click **Create > Triggered Task > User-defined Script**
3. Configure as follows:

#### **1st Tab (General)**

- **Task Name**: `Homebrew Boot`
- **User**: `root`
- **Event**: `Boot-up`
- **Enabled**: ✅

#### **2nd Tab (Script)**

Paste this into the **User-defined script** box:

```bash
#!/bin/bash

# Ensure /home exists
[[ ! -d /home ]] && sudo mkdir /home

# Only mount if it's not already a mountpoint
if ! grep -qs ' /home ' /proc/mounts; then
  sudo mount -o bind "$(readlink -f /var/services/homes)" /home
fi

# Permission fixes
sudo chown root:root /home
sudo chmod 775 /home

if [[ -d /home/linuxbrew ]]; then
  sudo chown root:root /home/linuxbrew
  sudo chmod 775 /home/linuxbrew
fi
```
---

## 🛠️ Configure Packages with `config.yaml`

If you chose **Advanced Install**, your setup is driven by a YAML configuration file.

This file lets you define exactly what packages, plugins, themes, and aliases to install. It’s fully customizable — just edit the actions or add your own!

---

### 📂 File Location

After cloning this repo, you'll find the config file at:

```bash
~/Synology-Homebrew/config.yaml
```

Open it in your favorite editor:

```bash
nvim ~/Synology-Homebrew/config.yaml
# or
nano ~/Synology-Homebrew/config.yaml
```

---

### ⚙️ Available Actions

Each item (package, plugin, etc.) supports three actions:

- `install`: install it
- `uninstall`: remove it (if installed)
- `skip`: ignore it (leave it as-is)

---

### 📦 Example: Packages Section

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
  eza:
    action: install
    aliases:
      ls: "eza --color=always --group-directories-first --icons"
      ll: "eza -la --icons --octal-permissions --group-directories-first --icons"
      l: "eza -bGF --header --git --color=always --group-directories-first --icons"
      llm: "eza -lbGd --header --git --sort=modified --color=always --group-directories-first --icons"
      la: "eza --long --all --group --group-directories-first"
      lx: "eza -lbhHigUmuSa@ --time-style=long-iso --git --color-scale --color=always --group-directories-first --icons"
      lS: "eza -1 --color=always --group-directories-first --icons"
      lt: "eza --tree --level=2 --color=always --group-directories-first --icons"
      l.: "eza -a | grep -E '^\\.'"
    eval: []
  zoxide:
    action: install
    aliases:
      cd: "z"
    eval:
      - "zoxide init zsh"
```

---

### 🎨 Example: Plugins Section

```yaml
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

### 🧠 Pro Tips

- Use `aliases` to override default commands (e.g. `ls → eza`)
- Use `eval` to inject shell behavior after installing a package
- Skip unused packages instead of deleting them — easier to toggle later
- You can comment out any section using `#`

---

### 🔄 Applying Changes

You can re-run the installer any time:

```bash
~/Synology-Homebrew/install-synology-homebrew.sh
```

It will re-read your updated `config.yaml` and apply the new actions.

---

## 📦 Installed Packages (Advanced View)

These are the packages installed when using the **Advanced Install** option in `config.yaml`.

<details>
<summary>📦 Click to view full list of installed packages (Advanced Install)</summary>

<br>

| Package | Description | Dependency |
|--------|-------------|------------|
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

## ✨ Neovim Setup

Neovim (`nvim`) is fully supported and enhanced out of the box — ready for power users.

You can choose to run a custom config or use the **kickstart.nvim** template for a smart default.

---

### 📁 Neovim Config Script

This repo includes a helper script:  
```bash
~/Synology-Homebrew/nvim_config.sh
```

Run it manually to:

- Enable system clipboard over SSH via OSC52
- Install Python support for linting and plugins
- Setup Ruby gem support
- Add helpful scripts like `fzf-git.sh` for Git integration

```bash
bash ~/Synology-Homebrew/nvim_config.sh
```

---

### 🚀 Using Kickstart.nvim (optional template)

Want a clean, fast Neovim config with everything pre-wired?

1. In `config.yaml`, find the `plugins:` section
2. Set `kickstart.nvim` to `action: install`

```yaml
plugins:
  kickstart.nvim:
    action: install
    url: "https://github.com/nvim-lua/kickstart.nvim"
    directory: "~/.config/nvim-kickstart"
    aliases:
      nvim: 'NVIM_APPNAME="nvim-kickstart" nvim'
```

---

### 🔄 Switching Between Configs

In your `~/.zshrc`, add an alias to switch Neovim configs easily:

```zsh
# Kickstart config
alias nvim="NVIM_APPNAME='nvim-kickstart' nvim"

# Your own config
alias nvim="NVIM_APPNAME='nvim-mrcee' nvim"
```

If no alias is set, Neovim defaults to:

```bash
~/.config/nvim
```

---

### ✅ Final Step: Health Check

After installation, launch Neovim:

```bash
nvim
```

Then, inside Neovim, run:

```
:checkhealth
```

This will check your environment and highlight any missing dependencies, misconfigured plugins, or setup issues.

💡 If you've configured aliases via `.zshrc`, be sure you're launching the correct Neovim app profile:

```bash
NVIM_APPNAME="nvim-kickstart" nvim
```

<img src="screenshots/SCR-neovim-plugins-updated.png" width="800">

---

## 🖌️ Customize Your Zsh

Your shell environment comes preloaded with:

- `zsh` + `oh-my-zsh`
- The `powerlevel10k` theme
- Helpful plugins (e.g. autosuggestions, syntax highlighting)
- Useful command aliases (like `ll`, `vim → nvim`, `cat → bat`, `cd → zoxide`, `ls → eza`)


Customize further with:

```bash
p10k configure
```

This interactive wizard lets you choose your preferred prompt style, icons, spacing, and color themes.

For a full walkthrough and recommended iTerm2 settings, check the [iTerm2 Configuration Guide →](https://github.com/MrCee/Synology-Homebrew/wiki/iTerm2-Configuration)

<img src="screenshots/SCR-iTerm2.png" width="800">

---

## 🧑‍💻 Usage & Contributions

- Refer to official [Homebrew documentation](https://docs.brew.sh) for basic usage
- To re-run or update your setup:  
  ```bash
  ~/Synology-Homebrew/install-synology-homebrew.sh
  ```
- Need help or want to improve the project?  
  Submit issues, pull requests, or questions on [GitHub](https://github.com/MrCee/Synology-Homebrew/issues)

---

## ⚖️ Disclaimer & License

This script is provided **as-is** with no warranties.  
Please **review and understand** changes before applying them to your system.

Licensed under the [MIT License](LICENSE).

---

## 🙏 Acknowledgements

Big thanks to the open source projects and creators that made this possible, including:

- Everyone contributing to brew
- @ogerardin, @AppleBoiy, @josean-dev, @tjdevries
- The GitHub & Synology dev communities
- Everyone contributing ideas, scripts, and support 🎉

---

## ☕ Support the Project

If this saved you hours or you just love clean terminal setups:

<a href="https://www.buymeacoffee.com/MrCee" target="_blank">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-violet.png" width="200">
</a>


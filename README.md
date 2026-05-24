# Synology-Homebrew

[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/MrCee/Synology-Homebrew/pulls)
[![Last Commit](https://img.shields.io/github/last-commit/MrCee/Synology-Homebrew)](https://github.com/MrCee/Synology-Homebrew/commits)
[![Platform](https://img.shields.io/badge/Platform-DSM%207.2%2B%20%7C%20macOS-1C1C1C)](https://www.synology.com/en-global/dsm)
[![Architecture](https://img.shields.io/badge/Architecture-x86__64%20%7C%20ARM64-1793D1)](https://en.wikipedia.org/wiki/X86-64)

Practical Homebrew bootstrap and shell tooling for Synology DSM, with matching macOS support for people who want the same package set on a Mac.

This repository is the public source of truth for the installer, uninstall flow, zsh hardening, and the current Neovim integration.

| Area | Included |
| --- | --- |
| 🧰 Homebrew/Linuxbrew | Basic and Advanced install flows |
| 🐚 zsh | Oh My Zsh, Powerlevel10k, plugins, completion hardening |
| 📝 Neovim | Canonical `nvim-mrcee` config via `NVIM_APPNAME` |
| 🧹 Uninstall | Conservative cleanup for managed paths only |

---

## 🧭 What This Project Does

Synology-Homebrew installs and maintains a Homebrew/Linuxbrew environment without replacing Synology system packages.

It can:

- install Homebrew on Synology DSM or macOS
- prepare the Synology `/home` layout Homebrew expects
- install a conservative baseline package set
- optionally apply a richer `config.yaml` package/plugin profile
- configure zsh, Oh My Zsh, Powerlevel10k, aliases, and shell integrations
- install Neovim and its language providers
- install the canonical public Neovim config from [`MrCee/nvim-mrcee`](https://github.com/MrCee/nvim-mrcee)
- uninstall Homebrew, Oh My Zsh, and only known-safe Neovim config/state paths

macOS support is included so the same `config.yaml` can be used for local development or parity with a Synology NAS.

---

## ✅ Current Status

| Area | Status |
| --- | --- |
| DSM 7.2+ | Tested and recommended |
| DSM 7.1 | Allowed, best effort |
| DSM older than 7.1 | Blocked |
| Synology x86_64 | Supported |
| Synology ARM64 / aarch64 | Supported where Homebrew supports the platform |
| 32-bit ARM / i386 | Blocked by design |
| macOS Apple Silicon | Supported via `/opt/homebrew` |
| macOS Intel | Supported via `/usr/local` |

The installer performs upfront CPU architecture checks. Homebrew does not support 32-bit platforms, so those systems are blocked early instead of failing halfway through the Homebrew installer.

---

## ✨ Key Features

- Two install modes: Basic and Advanced
- Synology/Linuxbrew install root at `/home/linuxbrew/.linuxbrew`
- macOS Homebrew roots handled automatically
- Minimal baseline mode with an optional safe prune prompt
- YAML-driven Advanced mode using `config.yaml`
- Non-interactive Oh My Zsh install
- Powerlevel10k theme setup
- zsh autosuggestions and syntax highlighting support
- zsh completion permission hardening before final shell handoff
- Neovim bootstrap using `NVIM_APPNAME="nvim-mrcee"` when needed
- Uninstall flow with conservative Neovim cleanup rules

---

## ⚠️ Important Safety Notes

- Do not run `install-synology-homebrew.sh` as root. Run it as your normal user; it will request sudo when required.
- The installer creates a temporary sudoers fragment during a run and removes it during cleanup.
- Synology user homes must be enabled in DSM before installation.
- Synology uses `/home` as a bind mount to `/var/services/homes`; the installer prepares this for the active session.
- Homebrew is isolated from DSM packages, but the installer does create compatibility files such as `/usr/bin/ldd` and `/etc/os-release` on Synology.
- Advanced mode edits shell files such as `~/.zshrc`.
- Existing user Neovim configs are not blindly overwritten.
- Uninstall is intentionally conservative around unknown Neovim directories.

---

## 🚀 Install

### Basic

Basic mode installs Homebrew plus the platform baseline packages. It ignores optional packages and plugins in `config.yaml`.

```zsh
git clone https://github.com/MrCee/Synology-Homebrew.git ~/Synology-Homebrew
~/Synology-Homebrew/install-synology-homebrew.sh
```

Choose `1` when prompted.

Baseline packages:

| Platform | Packages |
| --- | --- |
| Synology/Linux | `binutils glibc gcc git ruby python3 zsh yq` |
| macOS | `git yq ruby python3 coreutils findutils gnu-sed grep gawk` |

At the end of Basic mode, the installer can optionally prune extra explicitly installed leaf formulas back to the baseline. It does not remove dependencies that are still required by remaining formulas or Homebrew itself.

### Advanced

Advanced mode installs the baseline first, then applies `config.yaml`.

```zsh
git clone https://github.com/MrCee/Synology-Homebrew.git ~/Synology-Homebrew
cd ~/Synology-Homebrew
$EDITOR config.yaml
./install-synology-homebrew.sh
```

Choose `2` when prompted.

Each package or plugin in `config.yaml` uses an action:

| Action | Meaning |
| --- | --- |
| `install` | Install or update the item |
| `uninstall` | Remove the item where the script owns the path |
| `skip` | Leave the item alone |

---

## 🛠️ Advanced Mode Details

### 🧰 Homebrew / Linuxbrew

On Synology and Linux, Homebrew is installed under:

```zsh
/home/linuxbrew/.linuxbrew
```

On macOS, the standard Homebrew locations are used:

```zsh
/opt/homebrew   # Apple Silicon
/usr/local      # Intel
```

The installer writes the appropriate Homebrew shell environment into the platform profile file so `brew` is available in future shells.

### 🐚 zsh

Advanced mode configures zsh as the interactive shell experience after the installer finishes. On Synology, Homebrew's zsh is symlinked at `/bin/zsh` and the final installer step hands the session to zsh.

### 🧩 Oh My Zsh

Oh My Zsh is installed non-interactively by cloning the upstream repository. The installer disables Oh My Zsh update prompts during setup and ensures the expected source line is present in `~/.zshrc`.

### ⚡ Powerlevel10k

Powerlevel10k is cloned into the Oh My Zsh custom theme directory when enabled in `config.yaml`. The installer also places the theme selection before the Oh My Zsh source line so the prompt loads correctly.

### 🔌 Plugins And Tools

The default Advanced profile currently includes useful shell and editor tools such as:

| Tool | Purpose |
| --- | --- |
| `jq`, `yq` | Structured data processing |
| `ripgrep`, `fd`, `fzf` | Search and fuzzy finding |
| `bat`, `eza`, `git-delta` | Better terminal output |
| `zoxide`, `lazygit` | Navigation and Git workflows |
| `node`, `python3`, `ruby`, `perl` | Runtime/provider support |
| `zsh-autosuggestions`, `zsh-syntax-highlighting` | zsh usability |

The authoritative package and plugin list is [`config.yaml`](./config.yaml).

### 📝 Neovim Using nvim-mrcee

Advanced mode can install Neovim and the canonical public config:

```zsh
https://github.com/MrCee/nvim-mrcee
```

The preferred config path is:

```zsh
~/.config/nvim-mrcee
```

This avoids depending on `~/.config/nvim`, which is a common location for personal Neovim configs.

---

## 📝 Neovim

The canonical Neovim config for this project is [`MrCee/nvim-mrcee`](https://github.com/MrCee/nvim-mrcee).

When Advanced mode installs the Neovim profile:

- `neovim` is installed through Homebrew
- Python provider support is created under `~/.local/share/neovim-python`
- Node, npm, Ruby gem, and fzf helper setup is handled for the editor workflow
- the canonical config is cloned or updated from `https://github.com/MrCee/nvim-mrcee`
- when the config lives at `~/.config/nvim-mrcee`, the shell alias uses:

```zsh
alias nvim="NVIM_APPNAME=\"nvim-mrcee\" nvim"
```

### Config Directory Behaviour

The installer is deliberately cautious:

- If `~/.config/nvim` is absent or empty, the canonical repo may be installed there.
- If `~/.config/nvim` is already the canonical repo, it can be updated with `git pull --ff-only`.
- If `~/.config/nvim` contains an existing user config, it is left untouched.
- In that case, the canonical config is installed at `~/.config/nvim-mrcee` and selected with `NVIM_APPNAME="nvim-mrcee"`.

For ongoing use, `~/.config/nvim-mrcee` is preferred over `~/.config/nvim` because it keeps this repo's maintained config separate from any personal default Neovim setup.

---

## 🧯 zsh Completion Hardening

Synology can expose completion-related directories with permissions that zsh considers insecure. When Oh My Zsh runs `compinit`, this can surface as:

- `compaudit` warnings about insecure directories
- `compinit` refusing or prompting during shell startup
- missing `compdump`/autoload behaviour when zsh function paths are incomplete
- stale `~/.zcompdump` files carrying bad state between runs

Advanced mode now hardens this before the final zsh handoff by:

- inserting a zsh function-path guard before Oh My Zsh loads
- keeping Homebrew zsh function directories available in `fpath`
- removing group/other write permissions from Oh My Zsh and active Homebrew zsh completion directories
- deleting stale `~/.zcompdump*` files so zsh rebuilds completion state cleanly

Do not treat `ZSH_DISABLE_COMPFIX=true` as the main fix. It can suppress Oh My Zsh's warning, but it does not correct the underlying permissions or function-path problem.

---

## 🧹 Uninstall

Run the uninstall script from the repository:

```zsh
cd ~/Synology-Homebrew
./uninstall-synology-homebrew.sh
```

The uninstall flow can remove:

- Homebrew using Homebrew's official non-interactive uninstall script
- Synology compatibility files created by this project
- `/home/linuxbrew` on Synology after Homebrew removal
- Oh My Zsh at `~/.oh-my-zsh`
- `~/.zshrc`, `~/.p10k.zsh`, Powerlevel10k cache files, and related package-manager cache paths
- canonical Neovim config/state when you opt in

### Neovim Cleanup Rules

If you choose to remove Neovim config and cached files, uninstall checks both:

```zsh
~/.config/nvim
~/.config/nvim-mrcee
```

It removes a directory only when one of these is true:

- it is a git checkout whose origin is `https://github.com/MrCee/nvim-mrcee`
- it is a tiny non-git `~/.config/nvim` leftover of at most 16 KiB and at most 3 files

It does not remove large unknown user configs, non-canonical git checkouts, or substantial personal `~/.config/nvim` directories.

---

## 🧪 Verification Commands

After install, useful checks are:

```zsh
brew doctor
```

```zsh
zsh -ic 'autoload -Uz compinit && compinit -D && echo compinit-ok'
```

```zsh
NVIM_APPNAME="nvim-mrcee" nvim --headless "+checkhealth" "+qa"
```

On Synology, also confirm Homebrew is coming from the Linuxbrew prefix:

```zsh
command -v brew
brew --prefix
```

Expected prefix:

```zsh
/home/linuxbrew/.linuxbrew
```

---

## 🩺 Troubleshooting

### Insecure Completion Directories

If zsh reports insecure completion directories, inspect them with:

```zsh
compaudit
```

Advanced mode should remove group/other write bits from Oh My Zsh and Homebrew zsh completion paths. If you changed permissions after install, rerun Advanced mode or manually correct the listed directories.

### `compdump` Missing

If zsh cannot autoload `compdump`, the shell's `fpath` is likely missing zsh function directories. Advanced mode writes a guarded block into `~/.zshrc` before Oh My Zsh loads so Homebrew and system zsh function paths are available.

### Stale `.zcompdump`

If completion keeps failing after permissions are fixed, remove stale dumps and start a new shell:

```zsh
rm -f ~/.zcompdump*
exec zsh -il
```

### Homebrew Temp Sticky-Bit Warning

On Synology, Homebrew may warn if temporary paths are on DSM's small system volume or have unexpected permissions. This installer sets:

```zsh
HOMEBREW_TEMP="$HOME/tmp"
TMPDIR="$HOMEBREW_TEMP"
```

for the installer run so large Homebrew work happens under the user's home area rather than DSM's small system partition.

### Neovim Config Leftovers

If `nvim` starts with the wrong config, check the alias and app config:

```zsh
alias nvim
ls -la ~/.config/nvim ~/.config/nvim-mrcee 2>/dev/null
git -C ~/.config/nvim-mrcee remote get-url origin
```

The maintained config should come from:

```zsh
https://github.com/MrCee/nvim-mrcee
```

If you keep a personal `~/.config/nvim`, use `NVIM_APPNAME="nvim-mrcee"` for this project's config.

---

## 📌 Repository Notes

- Public repository: [`MrCee/Synology-Homebrew`](https://github.com/MrCee/Synology-Homebrew)
- Canonical Neovim config: [`MrCee/nvim-mrcee`](https://github.com/MrCee/nvim-mrcee)
- Main installer: [`install-synology-homebrew.sh`](./install-synology-homebrew.sh)
- Uninstaller: [`uninstall-synology-homebrew.sh`](./uninstall-synology-homebrew.sh)
- Advanced profile: [`config.yaml`](./config.yaml)

This project is maintained as a practical utility repo. Changes should keep the installer auditable, avoid destructive assumptions, and preserve user-owned configs unless the path is known to be managed by this project.

---

## License

This project is licensed under the [MIT License](./LICENSE).

---

## Support

<p align="left">
  <a href="https://www.buymeacoffee.com/MrCee" target="_blank" rel="noopener">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-violet.png" width="200" alt="Buy Me A Coffee">
  </a>
</p>

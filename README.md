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
| macOS Intel | Best effort via `/usr/local`; upstream Tier 3 |

The installer performs upfront CPU architecture checks. Homebrew does not support 32-bit platforms, so those systems are blocked early instead of failing halfway through the Homebrew installer.

Intel Macs are detected automatically; use the same installer command as on other platforms. The [Intel bootstrap route](#intel-macos-including-tahoe) avoids the Apple Silicon restriction in Homebrew's current installer. Intel macOS remains [upstream Tier 3](https://docs.brew.sh/Support-Tiers), so packages may require source builds or fail individually.

---

## ✨ Key Features

- Basic and Advanced install modes, plus an optional macOS background package stage
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

### Installation Order

You do not need Homebrew or `yq` installed before running this script. Both Basic and Advanced mode follow this order:

1. Reuse Homebrew at the platform prefix, or install it if absent.
2. Initialise Homebrew's environment and set up `yq` first. On Intel macOS, reuse a working `yq` or download the verified official standalone binary directly, without attempting `brew install yq`.
3. On Apple Silicon and Linux, attempt the Homebrew `yq` install, with the same standalone download as a fallback.
4. Attempt every remaining baseline package, reporting errors without skipping later package attempts.
5. In Advanced mode, validate `config.yaml` with the working `yq`, then process its packages, plugins and shell configuration. Basic mode ignores the YAML profile.

Homebrew setup errors are displayed directly. The installer stops if Homebrew itself cannot be set up, or if Advanced mode still has no working `yq` after bootstrap attempts fail. Other package failures are reported while the installer continues; reaching the end does not mean every package installed successfully.

The standalone download is official `yq` v4.44.3 for macOS or Linux on Intel/ARM64. Its pinned SHA-256 is checked before execution. It is stored at `~/.local/share/synology-homebrew/bin/yq`, separate from Homebrew-managed files, and activated for the installer and its child scripts. That activation does not add the fallback to future interactive shells automatically.

On Intel macOS, the installer also skips the blanket `brew upgrade` step so it cannot pull an existing Homebrew `yq` or unrelated packages into source builds. Other requested packages are still attempted and may compile from source. Apple Silicon and Linux retain the existing Homebrew upgrade step. No previously installed compilers or dependencies are removed.

### Intel macOS, Including Tahoe

Homebrew's current upstream installer rejects Intel Macs before installation. On Intel macOS, this script automatically selects official installer revision [`0f5b7666a65fc2d1a2615549f02771353c250f9a`](https://github.com/Homebrew/install/blob/0f5b7666a65fc2d1a2615549f02771353c250f9a/install.sh), which retains the `/usr/local` bootstrap and accepts Tahoe's version number. Apple Silicon and Linux use the current upstream installer.

This pins only the bootstrap script, not Homebrew itself or package versions. An existing Homebrew executable at the platform prefix is reused even if it is absent from `PATH`. No Intel-specific flags or separate installation command are needed. Intel Tahoe package compatibility still depends on Homebrew and each package; this route is not a guarantee that the full installation has been tested on your Mac model.

### Update an Existing Checkout

To get the current integrated installer, run these commands inside your existing checkout:

```zsh
cd ~/Synology-Homebrew
git switch main
git pull --ff-only
bash ./install-synology-homebrew.sh
```

If Git reports local changes or divergent history, keep those changes and resolve that message before retrying the update. Do not reset your checkout or replace a customised `config.yaml` just to update the installer.

### Fresh Synology NAS: install Git first

This project is normally installed with `git clone`. On a new DSM system, Git may not be installed yet.

Use this sequence on a fresh Synology NAS:

| Stage | Action |
| --- | --- |
| Stage 0 | Get Git working through DSM Package Center, SynoCommunity, or the companion [`MrCee/Synology-Git`](https://github.com/MrCee/Synology-Git) bootstrap helper. |
| Stage 1 | Clone this Synology-Homebrew repository. |
| Stage 2 | Run the Homebrew/Linuxbrew installer from the cloned repository. |

The Homebrew installer can check for Git after it starts and can try to install it through SynoCommunity. That helps during the installer run, but the normal public install path uses `git clone`, so Git must exist before this repository can be downloaded.

Some DSM systems may have `wget`, `curl`, Python, or direct ZIP download options available, and portable/static Git binaries may be theoretically possible. Those are not the supported default path because Synology DSM varies by CPU architecture, DSM version, libc/toolchain expectations, package availability, TLS/certificate behaviour, and permissions. Prefer Synology-native Git installation paths: DSM Package Center, SynoCommunity, or [`Synology-Git`](https://github.com/MrCee/Synology-Git).

### Basic

Basic mode installs Homebrew plus the platform baseline packages. It ignores optional packages and plugins in `config.yaml`.

Fresh Synology note: if `git clone` is not available, complete Stage 0 above first.

```zsh
git clone https://github.com/MrCee/Synology-Homebrew.git ~/Synology-Homebrew
~/Synology-Homebrew/install-synology-homebrew.sh
```

Choose `1` when prompted.

Baseline packages:

| Platform | Packages |
| --- | --- |
| Synology/Linux | `yq binutils glibc gcc git ruby python3 zsh` |
| macOS | `yq git ruby python3 coreutils findutils gnu-sed grep gawk` |

At the end of Basic mode, the installer can optionally prune extra explicitly installed leaf formulas back to the baseline. It does not remove dependencies that are still required by remaining formulas or Homebrew itself.

### Advanced

Advanced mode follows the installation order above, then validates and applies `config.yaml`. YAML validation runs after Homebrew and `yq` setup; it does not require a preinstalled `yq` or a separate Ruby/Psych validation step.

Fresh Synology note: if `git clone` is not available, complete Stage 0 above first.

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

### macOS Background Builds and Intel/Tahoe Guidance

On macOS, choose **3** to prepare Homebrew, Oh My Zsh, Powerlevel10k and the selected shell plugins first. Then choose **Start now** or **Compile later** for the package queue. After cleanup, an interactive installation opens the prepared zsh/Powerlevel10k shell in the same terminal. Both open the same floating progress window; Compile later stays paused until **Resume**. Package aliases and shell integrations check for their commands at each shell startup, so missing tools do not break the new shell and become available in new terminals after installation. Package-dependent setup, including Neovim providers, remains for **Finish setup…** after the queue completes. The queue reuses already installed formulas, including earlier foreground installs. Once started, unfinished work resumes at login after a restart; a deliberately paused or stopped queue stays paused. **Stop queue** stops the current build but retains progress for option **3** or **Resume**. The two Synology menu choices are unchanged.

See the [Intel macOS and background-build guide](docs/intel-macos.md) for what changed upstream, setup on your MacBook, the separate queue command, progress/retry controls, and LaunchAgent lifecycle. This new workflow is macOS-only; the Synology install choices are unchanged.

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

### 🔁 Synology Reboot Startup

The installer mounts `/home` for the current run. On Synology, that mount does not necessarily survive a DSM reboot, so create a DSM Scheduled Task if you want the Linuxbrew path prepared automatically after each startup.

DSM path:

```text
Control Panel -> Task Scheduler -> Create -> Triggered Task -> User-defined script
```

Recommended settings:

| Setting | Value |
| --- | --- |
| User | `root` |
| Event | `Boot-up` |
| Enabled | yes |

Script:

```bash
#!/bin/bash
[[ ! -d /home ]] && mkdir /home

if ! grep -qs ' /home ' /proc/mounts; then
  mount -o bind "$(readlink -f /var/services/homes)" /home
fi

chown root:root /home
chmod 775 /home

if [[ -d /home/linuxbrew ]]; then
  chown root:root /home/linuxbrew
  chmod 775 /home/linuxbrew
fi
```

This task does not start Homebrew as a service. It only restores the expected `/home` mount and permissions so shells can find `/home/linuxbrew/.linuxbrew` after a reboot.

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

### Homebrew Says Apple Silicon Only on an Intel Mac

If you see `Homebrew on macOS is only supported on Apple Silicon processors!`, update this repository using the existing-checkout commands above and rerun the main script. The integrated Intel route should print:

```text
Intel Mac detected: using the pinned Intel-compatible Homebrew installer (/usr/local).
```

This message appears when bootstrapping Homebrew on an Intel Mac; an existing installation is reused instead. Changing YAML or reinstalling Tahoe does not address this upstream installer restriction.

### Missing yq or a YAML Error

Older script versions could label a missing or incompatible `yq` as invalid YAML because the parser error was hidden. The current installer sets up `yq` before validation and shows the actual parser errors. Intel macOS uses a working existing executable or the verified standalone download directly; Apple Silicon and Linux use that download if Homebrew cannot supply a working version.

Update the checkout and rerun the installer. If `yq` bootstrap fails, inspect the displayed errors, including download, checksum or executable-compatibility failures. If `yq` is ready and reports a YAML syntax error, correct the indicated location in `config.yaml`; removing validation will not make malformed YAML usable by later package and plugin processing.

### High CPU While Installing yq on Intel macOS

Output such as `./make.bash`, `configure` or compiler commands means Homebrew is building from source. Building `yq` through Homebrew can pull in Go and Pandoc, with Pandoc adding Haskell build dependencies. The current Intel route avoids this `yq` build chain by using the verified standalone executable first. If an older installer is still building it, interrupt that run with Control+C, update this checkout, and rerun. Other requested packages may still need compilation; already installed dependencies are retained.

### `git clone` Is Not Available

On a fresh Synology DSM system, `git clone` may fail because Git is not installed yet. Install Git first through DSM Package Center, SynoCommunity, or the companion [`MrCee/Synology-Git`](https://github.com/MrCee/Synology-Git) helper, then rerun the Synology-Homebrew clone command.

This is a Stage 0 bootstrap step. Synology-Homebrew is the Stage 1 Homebrew/Linuxbrew environment installer and should be cloned after Git is working.

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
- Stage 0 Git bootstrap helper: [`MrCee/Synology-Git`](https://github.com/MrCee/Synology-Git)
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

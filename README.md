# Synology-Homebrew

- Neovim installed perfectly.
- Installer also supports macOS to sync same config on Intel & Apple silicon.

---

## Introduction

Simplify the installation of Homebrew on Synology NAS devices running DSM 7.2 or later with this script. This repository streamlines the process, ensuring comprehensive coverage of available packages for macOS/Linux on Synology. If you would like everything configured exactly the same way on macOS, it's covered here. The installer will replicate the config on macOS.

---

## Why Install Homebrew on Synology NAS or macOS?

Homebrew, a package manager for macOS and Linux, unlocks a vast ecosystem of modern software and libraries. Dive into the richer features as mentioned below.

---

## Key Features

- **Installation Options:**  
  Choose between a Minimal or Advanced installation. If you just want Homebrew to work, then the Minimal install is for you.

- **Profile Creation:**  
  Configures the default Synology `ash/sh` profile and newly installed `zsh` to work seamlessly with Homebrew.

- **Synology Integration:**  
  Resolves conflicts with existing Synology packages without removing anything from your NAS.

- **Easy Uninstall:**  
  Revert to the original state of your NAS with the included uninstall script.

- **Cross-Platform Compatibility:**  
  This same installer can be used on macOS. Linuxbrew and Homebrew will work with the `config.yaml` to provide the same experience, however you choose to configure it.

- **COMING SOON:**  
  A choice of terminal emulators preconfigured and further themes.

---

## Prerequisites

Before you begin, ensure the following setup:

1. **Synology NAS Requirements:**

   - A Synology NAS running DSM 7.2 or later.
   - SSH access enabled on your NAS.
   - User homes enabled on your NAS.
   - A scheduled task to ensure Homebrew is mounted after each restart (detailed instructions below).

2. **Synology Git Installation via CLI:**

   If Git is not already installed in your Synology environment, you can quickly install it via CLI. This will later be upgraded to Homebrew's Git version:

   ```bash
   curl -sSL https://raw.githubusercontent.com/MrCee/Synology-Git/refs/heads/main/install-synology-git.sh | bash
   ```

3. **iTerm2 Configuration:**

   Use **iTerm2** (or an alternative terminal emulator other than macOS Terminal.app) on your local machine for an improved experience.

   Ensure the following:

   - Compatible Nerd Fonts installed.
   - A configured color profile.

   Refer to the [iTerm2 Configuration Guide](https://github.com/MrCee/Synology-Homebrew/wiki/iTerm2-Configuration) for detailed setup instructions.

---

## Installation

### Quick Start:

SSH into your Synology NAS running DSM 7.2 or above and run the following command to download the installer into your home directory and execute it:

```bash
git clone https://github.com/MrCee/Synology-Homebrew.git ~/Synology-Homebrew && \
~/Synology-Homebrew/install-synology-homebrew.sh
```

### Select your install type:

#### 1) Minimal Install:

This will provide the Homebrew basics, ignore packages in `config.yaml`, leaving the rest to you.

_You can also use this option to uninstall packages in `config.yaml` installed by option 2 by running the script again._

#### 2) Advanced Install:

Full setup includes packages in `config.yaml`.

_Recommended if you want to get started with Neovim or install some of the great packages listed._

#### Both install types include the following essential packages to ensure Homebrew runs smoothly on Synology:

- git, ruby, glibc, gcc, python3, yq, zsh, oh-my-zsh.

## Configuration for Advanced install (`config.yaml`)

To manage packages, plugins, and themes, edit the `config.yaml` file and set the action flag to one of three options:

- **install**: Install the package, plugin, or theme.
- **uninstall**: Uninstall the package, plugin, or theme.
- **skip**: Do nothing, leaving the current state unchanged.

Plugins and themes can be defined under the **plugins** section. Plugin names will be updated to reflect the last part of the URL for consistency.

### **config.yaml example**

The below is a snippet of how `config.yaml` should be formatted. Please see the file downloaded from this repository for the full scope.

```yaml
packages:
  make:
    action: install
    aliases: []
    eval: []
  jq:
    action: install
    aliases: []
    eval: []
  perl:
    action: install
    aliases: []
    eval:
      - "perl -I$HOME/perl5/lib/perl5 -Mlocal::lib=$HOME/perl5"
  neovim:
    action: install
    aliases:
      vim: "nvim"
    eval: []
  stow:
    action: skip
    aliases: []
    eval: []
  fzf:
    action: install
    aliases: []
    eval:
      - "fzf --zsh"
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
  thefuck:
    action: install
    aliases: []
    eval:
      - "thefuck --alias"
  zoxide:
    action: install
    aliases:
      cd: "z"
    eval:
      - "zoxide init zsh"
  jesseduffield/lazygit/lazygit:
    action: install
    aliases:
      lg: "lazygit"
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

## Installed packages

Modify packages to be installed by editing config.yaml and setting the action flag to install, uninstall, or skip.

| Package                                                                         | Description                                                                                                 | Dependency                              |
| ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| [brew](https://brew.sh)                                                         | Homebrew - The Missing Package Manager now for MacOS & Linux.                                               | Essential for: Synology-Homebrew        |
| [git](https://git-scm.com)                                                      | Latest version replaces Synology Package Centre version.                                                    | Essential for: Synology-Homebrew        |
| [ruby](https://www.ruby-lang.org)                                               | Latest version replaces Synology Package Centre version.                                                    | Essential for: Synology-Homebrew        |
| [zsh](https://www.zsh.org)                                                      | UNIX shell (command interpreter).                                                                           | Essential for: Synology-Homebrew        |
| [python3 / pip3](https://www.python.org)                                        | Latest version installed.                                                                                   | Essential for: Synology-Homebrew        |
| [glibc](https://www.gnu.org/software/libc)                                      | The GNU C Library - The project provides the core libraries for the GNU system.                             | Essential for: Synology-Homebrew        |
| [gcc](https://gcc.gnu.org)                                                      | GNU compiler collection.                                                                                    | Essential for: Synology-Homebrew        |
| [oh-my-zsh](https://ohmyz.sh)                                                   | Oh My Zsh is a delightful, open source, community-driven framework for managing your Zsh configuration.     | Essential for: Synology-Homebrew, zsh   |
| [jq](https://jqlang.github.io/jq)                                               | Latest version of Lightweight and flexible command-line JSON processor                                      | Essential for: Synology-Homebrew        |
| [make](https://www.gnu.org/software/make)                                       | Utility for directing compilation.                                                                          | Essential for: neovim plugins           |
| [node](https://nodejs.org)                                                      | JavaScript runtime environment.                                                                             | Essential for: neovim                   |
| [neovim](https://neovim.io)                                                     | Hyperextensible Vim-based text editor.                                                                      | Recommended for: Synology               |
| [powerlevel10k](https://github.com/romkatv/powerlevel10k)                       | A theme for zsh.                                                                                            | Recommended for: oh-my-zsh              |
| [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) | A plugin for zsh.                                                                                           | Recommended for: oh-my-zsh              |
| [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)         | A plugin for zsh.                                                                                           | Recommended for: oh-my-zsh              |
| [ripgrep](https://github.com/BurntSushi/ripgrep)                                | Ripgrep is a line-oriented search tool that recursively searches the current directory for a regex pattern. | Essential for: neovim, telescope, fzf   |
| [fd](https://github.com/sharkdp/fd)                                             | Simple, fast and user-friendly alternative to find.                                                         | Essential for: neovim, telescope        |
| [fzf](https://github.com/junegunn/fzf)                                          | A command-line fuzzy finder.                                                                                | Essential for: neovim, telescope        |
| [fzf-git.sh](https://github.com/junegunn/fzf-git.sh)                            | Bash and zsh key bindings for Git objects.                                                                  | Recommended for: neovim, telescope, fzf |
| [bat](https://github.com/sharkdp/bat)                                           | A cat clone with syntax highlighting and Git integration.                                                   | Recommended for: zsh, neovim            |
| [git-delta](https://github.com/dandavison/delta)                                | Language syntax highlighting for diff using a Levenshtein edit inference algorithm.                         | Recommended for: neovim                 |
| [eza](https://github.com/eza-community/eza.git)                                 | A modern, maintained replacement for the venerable file-listing command-line program ls                     | Recommended for: zsh, neovim            |
| [tldr](https://github.com/tldr-pages/tldr)                                      | The tldr-pages project is a collection of community-maintained help pages for command-line tools            | Recommended for: neovim                 |
| [thefuck](https://github.com/nvbn/thefuck)                                      | A magnificent app that corrects errors in previous console command.                                         | Recommended for: zsh                    |
| [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim)                    | A starting point for Neovim.                                                                                | Optional for: neovim                    |
| [perl](https://www.perl.org)                                                    | Highly capable, feature-rich programming language.                                                          | Essential for: stow                     |
| [stow](https://www.gnu.org/software/stow)                                       | GNU Stow: Organize software neatly under a single directory tree.                                           | Optional                                |
| [zoxide](https://github.com/ajeetdsouza/zoxide)                                 | Zoxide is a smarter cd command, inspired by z and autojump                                                  | Recommended for: zsh                    |
| [lazygit](https://github.com/jesseduffield/lazygit)                             | **AMAZING** Simple terminal UI for git commands                                                             | Recommended for: zsh, neovim            |

## Neovim

Neovim (nvim) is ready to go with essential requirements configured within a separate file `nvim_config.sh` in which you can run indepenently to enable clipboard and further required files.
This includes:

- Enable clipboard over SSH using OSC52 for all nvim configurations stored or symlinked in `~/.config`.
- Linting Python with `pip3 install pynvim`.
- Installing neovim gem.
- Updating outdated gems.
- Adding fzf-git.sh with Git key bindings to `~/.scripts` directory.

### Kickstart Neovim with Lazy (optional)

In the plugins section of `config.yaml`, set `kickstart.nvim` action: install to configure Neovim with kickstart.nvim. This provides a lazy configuration with everything working out of the box. It will be installed to the specified directory in config.yaml with a backup of any existing config to your home folder.

To switch between Neovim configurations easily, use aliases in `~/.zshrc` and swap to your config:

```zsh
alias nvim="NVIM_APPNAME=\"nvim-kickstart\" nvim"

# or for example if you have your own nvim config...

alias nvim="NVIM_APPNAME=\"nvim-mrcee\" nvim"
```

See kickstart.nvim provided in the [config.yaml example](#configyaml-example) above.

If no alias is set, Neovim will attempt to use the default nvim config location `~/.config/nvim`

Run :checkhealth in Neovim after installation to see more detail about any further plugins you may need.

<img src="screenshots/SCR-neovim-plugins-updated.png" width="800">

## Customizing Your zsh

The Synology-Homebrew + Neovim setup comes pre-configured with a sleek Zsh theme and several useful plugins to enhance your command-line experience. Customize your zsh with ease using the `p10k configure` command and enjoy a fully tailored terminal environment.

<img src="screenshots/SCR-iTerm2.png" width="800">

## Synology Task Scheduler to Persist Installation after Restart

To ensure the Homebrew directory is mounted after each restart, add a Triggered Task with a User-defined script.
Go to Control Panel > Task Scheduler, click Create, and select Triggered Task >> User-defined Script and enter the following...

1st tab:

- Task name: "Homebrew Boot"
- User: root
- Event: Boot-up
- Enabled: True

2nd tab:

- Paste the following User-defined script...

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

## Usage and Contributions

Refer to Homebrew documentation for usage instructions. Contributions are welcome! Open an issue or submit a pull request on GitHub for feedback or suggestions.

## Disclaimer and License

This script is provided as-is without any warranty. Review and understand the script's changes to your system before running it. This project is licensed under the MIT License.

## Acknowledgements

Thanks to the many people and teams that contribute to the packages installed by this script, the GitHub & Synology community, and some of the best on youtube. @ogerardin, @AppleBoiy, @josean-dev, @tjdevries.

<a href="https://www.buymeacoffee.com/MrCee" target="_blank">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-violet.png" width="200">
</a>

# macOS companion setup

[Back to Synology-Homebrew](../README.md)

Synology DSM is the project's primary platform. This guide covers optional Mac
support, particularly Intel Macs affected by Homebrew's reduced binary support.
The Mac-specific package routes do not replace the Synology/Linuxbrew workflow.

## Running the installer on a Mac

Apple Silicon uses the existing Homebrew setup under `/opt/homebrew`. Intel uses
`/usr/local`, reuses Apple's baseline tools, and routes package installs through
verified binaries. Run the same interactive installer for its original Minimal,
Advanced and Background options:

```sh
cd ~/Synology-Homebrew
git pull --ff-only
bash ./install-synology-homebrew.sh
```

Keep local edits if Git refuses the pull; resolve them rather than discarding a
customised configuration. The interactive installer authenticates sudo before
installing missing Homebrew. It reuses Python 3.12+ when available, or installs
the SHA-256-verified official Python 3.13.17 macOS package and sets up its HTTPS
certificates before processing packages. This does not restore missing Intel bottles.

## Intel Mac binary-only setup

To guard ordinary `brew install` calls made by other scripts on this Mac, run
`python3 enable-binary-brew.py` once. This replaces `/usr/local/bin/brew` with a
small entry wrapper and preserves the original symlink as
`/usr/local/bin/brew.before-synobrew`.
Keep this checkout at its current location while the wrapper is enabled.

The wrapper routes formula installs through the binary-only installer, refuses
source/HEAD and unsupported install options, and blocks unguarded upgrade,
reinstall, bundle, postinstall and test commands. Read commands still use real
Homebrew. Existing formula versions are reused; this is not an automatic updater.
New tools without a compatible bottle fail rather than compile. Add a verified
binary source to the manifest when needed. Cask installation is currently refused.

The guarantee applies to these entry points. A script explicitly invoking
`/usr/local/Homebrew/bin/brew`, another package manager or a compiler can bypass
the wrapper. Legacy repo helpers also route brew calls through the guard; their
Python installs are wheel-only and npm lifecycle scripts are disabled on Intel.
The Intel Neovim helper installs binary Neovim/Node, then applies the YAML-selected
configuration and native plugins when explicitly enabled by Advanced setup.
Configured Mason language servers and formatting/linting tools are installed as well.

To remove the machine entry guard, restore the preserved symlink with:
`mv /usr/local/bin/brew.before-synobrew /usr/local/bin/brew`.

On Intel macOS, `./install-synology-homebrew.sh` retains the original interactive
Minimal / Advanced / Background menu, YAML package and plugin selection, shell
setup and final zsh handoff. Only package acquisition changes: Intel package
installs use `install-macos-binaries.py`, with no implicit Homebrew source builds.
Advanced setup enables native Neovim plugin builds, including Tree-sitter,
LuaSnip and Telescope, and installs configured Mason tools. These plugin builds
are separate from Homebrew formula builds. Intel setup does not create a
passwordless sudoers fragment or replace the existing shell profile.
Use `./install-synology-homebrew.sh --packages-only` for the package-only path.
Python 3.12+ and an existing Homebrew installation in `/usr/local` are required.
The interactive bootstrap exports the validated runtime as `SYNOBREW_PYTHON`
for package helpers and background workers. Explicit package-only and plan runs
require a prepared Python runtime (`SYNOBREW_PYTHON` can select it).
Run `./install-synology-homebrew.sh --plan` to display the Intel download routes
without installing, downloading or changing any packages. macOS Intel detection
happens before the legacy installer; Apple Silicon and Synology retain their
existing workflows. These Intel binaries must not be used on Linux.

- Reuses installed Homebrew formulae, then uses pinned Intel binaries in
  `upstream-binaries.json` where available.
- For remaining Homebrew formulae, a process-local guard refuses source builds
  for both requested formulae and dependencies. It supports Homebrew 7.0.x and
  refuses other versions until reviewed. Homebrew's files are not patched.
- Upstream binaries live in `~/.local/share/synology-homebrew/binaries` with
  command symlinks in `/usr/local/bin`. Unrelated existing commands are preserved.
- eza uses the self-contained conda-forge Intel binary, whose only declared
  dependency is macOS >=11; it does not install a conda package manager.
- Delta is pinned to 0.18.2 because the newer releases checked did not publish
  an Intel Mac asset. Its SHA256 was recorded from the official HTTPS release;
  other GitHub assets use release API digests and Node uses official SHASUMS256.
- Perl reuses Apple's system Perl. The Fuck uses an isolated Apple CLT Python
  3.9 environment with wheels only, because it imports `imp`, which newer Python
  releases removed. No global Python packages are changed.
- Normal Intel background queues are marked binary-only and use the same guarded
  package backend. Source queues require separate explicit approval; old queues
  without either policy cannot run or resume on Intel.

Use `python3 install-macos-binaries.py <formula> ...` for a subset. Results are
written after each package to `binary-install-results.json`; failures return a
nonzero status. The package-only command does not apply plugins or shell configuration; the
interactive Advanced installer does.

### Last resort: compile only when binaries are unavailable

Normal installation never enables compilation automatically. If a tool has no
usable bottle after binary alternatives have been tried, explicitly request:

```bash
python3 compile-macos-packages.py --allow-source-builds <formula>
```

This retries the binary-only path first. Only failures explicitly reported by
the build guard as a missing usable bottle are eligible for the source queue.
Network errors, checksum mismatches and unrelated install failures do not trigger
compilation. The command saves only those selected formulae, without adding the
whole baseline, and opens the custom floating progress window **paused**.
Choose **Resume** to start; **Stop queue** retains progress. Build parallelism
defaults to two jobs (`SYNOBREW_BUILD_JOBS=1` reduces it further).

```bash
bash background-packages.sh status
bash background-packages.sh window
bash background-packages.sh resume
bash background-packages.sh stop
```

Consent and the queue snapshot persist across logins. Running/interrupted work
resumes at the next desktop login; deliberately paused/stopped work stays paused.
Completed installed formulae and dependencies are reused. This is package-level
resumption: an interrupted formula's compiler work may restart. The rest of the
system remains binary-only; the source queue alone uses the preserved official
Homebrew entry. Compiler/toolchain installation is never silently enabled by
the binary-only installer.

## Background packages and status window

Menu option **3** prepares Oh My Zsh, Powerlevel10k and selected shell plugins,
then offers **Start now** or **Install later**. Install later saves a paused
queue. A terminal run hands off to zsh after cleanup. Once packages are ready,
choose **Finish setup** in the window or run Advanced mode to complete Neovim
and package integrations.

For an existing Homebrew installation, a binary-only Intel queue can also be
created directly:

```sh
bash ./background-packages.sh start ./config.yaml --binary-only
# Or save it paused:
bash ./background-packages.sh start ./config.yaml --binary-only --paused
```

The floating window provides progress, logs, pause, stop, resume and retry
controls. Closing or minimising the window does not stop the worker. Reopen it
with `bash ./background-packages.sh window`. The queue snapshots its YAML and
runs as the logged-in Mac user. Running or interrupted jobs resume at the next
desktop login; deliberately paused or stopped jobs stay paused. Completed
packages are reused. LaunchAgents and the native window are macOS-only and do
not add a Synology startup task.

## Troubleshooting

- **Homebrew says Apple Silicon only:** update this checkout and use its retained
  Intel bootstrap helper if Homebrew is missing. Reinstalling macOS does not
  restore upstream Intel support.
- **Unexpected compilation:** normal Intel package installs refuse source builds.
  Advanced Neovim setup allows its native plugin builds. Formula source builds
  require the explicit last-resort command above.
- **Wrong menu or missing zsh handoff:** check which checkout you ran. A second,
  older checkout may still contain an earlier Intel entry point.
- **Shell features missing after setup:** start a fresh interactive login shell
  with `exec /bin/zsh -il`. Minimal mode does not install the Advanced shell profile.

For shared YAML, shell completion and Neovim troubleshooting, return to the
[main README](../README.md#-troubleshooting).

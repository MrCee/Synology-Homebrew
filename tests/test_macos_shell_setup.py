"""Shell-first setup tests use a private HOME and fake Git; no downloads."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
YQ = shutil.which('yq')


@unittest.skipUnless(sys.platform == 'darwin' and YQ, 'Requires macOS zsh and yq')
class MacShellSetupTests(unittest.TestCase):
    def test_shell_ready_before_any_formulas_and_integrations_activate_later(self):
        with tempfile.TemporaryDirectory(prefix='shell first ') as temporary:
            root = Path(temporary)
            repo, home, binaries = root/'repo', root/'home', root/'bin'
            for path in (repo, home, binaries):
                path.mkdir()
            shutil.copy(REPO/'macos-shell-setup.sh', repo)
            shutil.copytree(REPO/'profile-templates', repo/'profile-templates')
            (repo/'functions.sh').write_text('''func_initialize_env_vars() { DARWIN=1; }
func_bootstrap_yq() { return 0; }
func_ensure_zsh_function_path_guard() { return 0; }
''')
            (binaries/'git').write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$HOME/git-calls"
for destination; do :; done
mkdir -p "$destination"
case "$destination" in
*/.oh-my-zsh) echo 'print -r -- "$ZSH_THEME|${plugins[*]}" > "$HOME/loaded-shell"' > "$destination/oh-my-zsh.sh" ;;
*/powerlevel10k) touch "$destination/powerlevel10k.zsh-theme" ;;
esac
''')
            (binaries/'git').chmod(0o755)
            (binaries/'brew').write_text('#!/bin/bash\necho unexpected-brew-call >> "$HOME/brew-calls"\nexit 1\n')
            (binaries/'brew').chmod(0o755)
            os.symlink(YQ, binaries/'yq')
            config = repo/'config.yaml'
            # Use the real profile to cover aliases, Perl and shell plugins.
            config.write_bytes((REPO/'config.yaml').read_bytes())
            zshrc = home/'.zshrc'
            original = '# keep user settings\nexport MY_SETTING=kept\n'
            zshrc.write_text(original)
            (home/'.p10k.zsh').write_text('# existing personal prompt\n')
            env = dict(os.environ, HOME=str(home), PATH=str(binaries)+':/usr/bin:/bin')
            for _ in range(2):
                result = subprocess.run(['/bin/bash', str(repo/'macos-shell-setup.sh'), str(config)], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            self.assertFalse((home/'brew-calls').exists())
            self.assertEqual(len((home/'git-calls').read_text().splitlines()), 4)
            self.assertFalse((home/'.config/nvim').exists())
            self.assertEqual((home/'.p10k.zsh').read_text(), '# existing personal prompt\n')
            self.assertEqual((home/'.zshrc.synology-homebrew-before-shell').read_text(), original)
            text = zshrc.read_text()
            self.assertIn(original, text)
            self.assertEqual(text.count('# >>> Synology-Homebrew shell preparation >>>'), 1)
            self.assertEqual(text.count('# >>> Synology-Homebrew package integrations >>>'), 1)
            self.assertLess(text.index('plugins=('), text.index('source "$ZSH/oh-my-zsh.sh"'))
            result = subprocess.run(['/bin/zsh', '-f', '-c', 'source "$HOME/.zshrc"; print -r -- "$MY_SETTING"; alias lg'], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)  # lazygit isn't installed yet
            self.assertEqual(result.stdout.strip(), 'kept')
            self.assertEqual(result.stderr, '')
            self.assertIn('powerlevel10k/powerlevel10k|git web-search zsh-syntax-highlighting zsh-autosuggestions', (home/'loaded-shell').read_text())
            (binaries/'lazygit').write_text('#!/bin/bash\nexit 0\n')
            (binaries/'lazygit').chmod(0o755)
            result = subprocess.run(['/bin/zsh', '-f', '-c', 'source "$HOME/.zshrc"; alias lg'], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), 'lg=lazygit')


class MacInstallerMenuTests(unittest.TestCase):
    def run_menu(self, timing, busy=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shutil.copy(REPO/'install-synology-homebrew.sh', root)
            (root/'config.yaml').write_text('packages: {}\n')
            (root/'functions.sh').write_text('''func_setup_logging() { :; }
func_initialize_env_vars() { DARWIN=1; HOMEBREW_PATH=/fake; USERNAME=test; USERGROUP=test; ROOTGROUP=test; }
func_cleanup_exit() { echo cleanup >> "$TEST_EVENTS"; }
func_sudoers() { SUDOERS_SETUP_DONE=1; }
func_git_commit_check() { :; }
func_ensure_homebrew() { echo brew-ready >> "$TEST_EVENTS"; }
func_bootstrap_yq() { echo yq-ready >> "$TEST_EVENTS"; }
func_persist_macos_brew_env() { :; }
''')
            (root/'macos-shell-setup.sh').write_text('echo shell-ready >> "$TEST_EVENTS"\n')
            (root/'background-packages.sh').write_text('''echo "queue $*" >> "$TEST_EVENTS"
if [[ "$1" == busy ]]; then exit "$TEST_BUSY_EXIT"; fi
''')
            env = dict(os.environ, TEST_EVENTS=str(root/'events'), TEST_BUSY_EXIT='0' if busy else '1', TERM='xterm')
            result = subprocess.run(['/bin/bash', str(root/'install-synology-homebrew.sh')], input='3\n'+timing+'\n', cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            self.assertNotIn('4) Homebrew', result.stdout)
            return (root/'events').read_text().splitlines()

    def test_start_now_prepares_shell_before_starting_queue(self):
        events = self.run_menu('1')
        self.assertIn('queue start ./config.yaml', events)
        self.assertLess(events.index('shell-ready'), events.index('queue start ./config.yaml'))

    def test_compile_later_prepares_shell_and_saves_paused(self):
        events = self.run_menu('2')
        self.assertIn('queue start ./config.yaml --paused', events)
        self.assertLess(events.index('shell-ready'), events.index('queue start ./config.yaml --paused'))

    def test_existing_queue_can_prepare_shell_without_replacing_progress(self):
        events = self.run_menu('2', busy=True)
        self.assertIn('queue pause', events)
        self.assertIn('queue window', events)
        self.assertFalse(any(event.startswith('queue start') for event in events))


if __name__ == '__main__':
    unittest.main()

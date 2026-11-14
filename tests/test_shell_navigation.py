"""Exercise the startup-order regression without installing any packages."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('navigation', REPO / 'fix-shell-navigation.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
ZSH = shutil.which('zsh')


class NavigationTests(unittest.TestCase):
    def test_only_the_legacy_alias_changes_and_repeated_runs_are_stable(self):
        original = '# user settings\nexport PERSONAL=kept\nalias cd="z"\nalias ll="ls -l"\n'
        result = MODULE.configure(original)
        self.assertNotIn('alias cd=', result)
        self.assertIn('export PERSONAL=kept', result)
        self.assertIn('alias ll="ls -l"', result)
        self.assertEqual(MODULE.configure(result), result)
        self.assertIn('alias cd=custom', MODULE.configure('alias cd=custom\n'))

    def test_truncated_managed_block_preserves_input(self):
        with self.assertRaises(ValueError):
            MODULE.configure('personal\n' + MODULE.START + '\nunfinished\n')

    @unittest.skipUnless(ZSH, 'Requires zsh')
    def test_fresh_shell_loads_zoxide_after_brew_and_cd_remains_native(self):
        with tempfile.TemporaryDirectory(prefix='navigation space ') as temporary:
            root = Path(temporary)
            home, binaries, destination = root / 'home', root / 'brew bin', root / 'scope works'
            for path in (home, binaries, destination):
                path.mkdir()
            brew = binaries / 'brew'
            brew.write_text('#!/bin/bash\nprintf "export PATH=%q:$PATH\\n" "$FAKE_BIN"\n')
            brew.chmod(0o755)
            zoxide = binaries / 'zoxide'
            zoxide.write_text('#!/bin/sh\nprintf \'%s\\n\' \'z() { builtin cd "$@"; }\'\n')
            zoxide.chmod(0o755)
            target = home / 'managed.zshrc'
            original = 'export PERSONAL=kept\nalias cd="z"\neval "$(zoxide init zsh)"\n'
            target.write_text(original)
            target.chmod(0o600)
            zshrc = home / '.zshrc'
            zshrc.symlink_to(target)
            env = dict(os.environ, HOME=str(home), FAKE_BIN=str(binaries),
                       TEST_DESTINATION=str(destination), PATH='/usr/bin:/bin')
            if str(Path(ZSH).parent) not in ('/usr/bin', '/bin'):
                env['PATH'] += ':' + str(Path(ZSH).parent)
            command = [sys.executable, str(REPO / 'fix-shell-navigation.py'),
                       '--write', '--brew', str(brew), str(zshrc)]
            first = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            second = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertTrue(zshrc.is_symlink())
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            backups = list((home / '.local/state/synology-homebrew/backups').iterdir())
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), original)
            result = subprocess.run([ZSH, '-f', '-c',
                'source "$HOME/.zshrc"; whence -w cd z; cd "$TEST_DESTINATION"; '
                'print -r -- "CD:$?:$PWD"; z "$HOME"; print -r -- "Z:$?:$PWD"; '
                'print -r -- "$PERSONAL"'], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, '')
            self.assertIn('cd: builtin', result.stdout)
            self.assertIn('z: function', result.stdout)
            self.assertIn('CD:0:' + str(destination), result.stdout)
            self.assertIn('Z:0:' + str(home), result.stdout)
            self.assertIn('kept', result.stdout)


if __name__ == '__main__':
    unittest.main()

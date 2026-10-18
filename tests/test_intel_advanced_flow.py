"""Exercise the original Advanced menu and final shell in an isolated HOME."""
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
YQ = shutil.which('yq')


@unittest.skipUnless(sys.platform == 'darwin' and YQ, 'Requires macOS zsh and yq')
class IntelAdvancedFlowTests(unittest.TestCase):
    def test_advanced_processes_yaml_plugins_shell_and_transports_last(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home, bins = root/'home', root/'bin'
            home.mkdir(); bins.mkdir()
            (home/'.config/nvim').mkdir(parents=True)
            (home/'.zshrc').write_text('print SHELL_HANDOFF_READY\nexit 0\n')
            shutil.copy(ROOT/'install-synology-homebrew.sh', root)
            (root/'config.yaml').write_text('packages:\n  neovim:\n    action: install\n  perl:\n    action: skip\nplugins:\n  mrcee.nvim:\n    action: install\n    directory: "~/.config/nvim"\n    url: "https://example.test/nvim"\n')
            (root/'functions.sh').write_text('''func_setup_logging() { :; }
func_initialize_env_vars() { DARWIN=1; HOMEBREW_PATH="$HOME/homebrew"; }
func_sudoers() { echo UNEXPECTED_SUDOERS >> "$EVENTS"; }
func_cleanup_exit() { echo cleanup >> "$EVENTS"; }
install_brew_and_packages() { echo baseline >> "$EVENTS"; }
func_harden_zsh_completion_permissions() { echo harden >> "$EVENTS"; }
''')
            for name, body in {
                'install-neovim.sh': 'echo neovim-config-and-plugins >> "$EVENTS"\n',
                'macos-shell-setup.sh': 'echo shell-setup >> "$EVENTS"\n',
                'background-packages.sh': 'exit 1\n',
            }.items():
                (root/name).write_text('#!/bin/bash\n'+body)
                (root/name).chmod(0o755)
            for name, body in {
                'uname': 'if [[ "$1" == -s ]]; then echo Darwin; else echo x86_64; fi\n',
                'python3': 'echo "binary-package ${@: -1}" >> "$EVENTS"\n',
                'sudo': 'echo UNEXPECTED_SUDO >> "$EVENTS"\nexit 1\n',
                'clear': ':\n',
                'brew': 'exit 1\n',
            }.items():
                (bins/name).write_text('#!/bin/bash\n'+body)
                (bins/name).chmod(0o755)
            (bins/'yq').symlink_to(YQ)
            env = dict(os.environ, HOME=str(home), EVENTS=str(root/'events'), PATH=str(bins)+':/usr/bin:/bin', TERM='xterm', SYNOBREW_PYTHON=str(bins/'python3'))
            master, slave = pty.openpty()
            proc = subprocess.Popen(['/bin/bash', str(root/'install-synology-homebrew.sh')], cwd=root, env=env, stdin=slave, stdout=slave, stderr=slave)
            os.close(slave)
            output = bytearray()
            os.write(master, b'2\n')
            try:
                deadline = time.monotonic()+20
                while time.monotonic()<deadline:
                    if select.select([master], [], [], .1)[0]:
                        try:
                            part=os.read(master,65536)
                        except OSError:
                            break
                        if not part: break
                        output.extend(part)
                    elif proc.poll() is not None: break
                proc.wait(timeout=3)
            finally:
                os.close(master)
                if proc.poll() is None: proc.kill(); proc.wait()
            text=output.decode(errors='replace')
            self.assertEqual(proc.returncode,0,text)
            events=(root/'events').read_text().splitlines()
            self.assertIn('binary-package neovim', events)
            self.assertIn('neovim-config-and-plugins', events)
            self.assertIn('shell-setup', events)
            self.assertEqual(events[-1], 'cleanup')
            self.assertFalse(any('UNEXPECTED' in e for e in events), events)
            self.assertIn('transported to zsh',text)
            self.assertIn('SHELL_HANDOFF_READY',text)
            self.assertLess(text.index('transported to zsh'), text.index('SHELL_HANDOFF_READY'))

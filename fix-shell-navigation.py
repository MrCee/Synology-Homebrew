#!/usr/bin/env python3
"""Prepare Homebrew before shell integrations and preserve native cd errors."""
import argparse
import datetime
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

START = '# >>> Synology-Homebrew navigation bootstrap >>>'
END = '# <<< Synology-Homebrew navigation bootstrap <<<'


def configure(text, brew='/home/linuxbrew/.linuxbrew/bin/brew'):
    lines = text.splitlines(keepends=True)
    output = []
    skipping = False
    for line in lines:
        value = line.strip()
        if value == START:
            skipping = True
            continue
        if value == END:
            skipping = False
            continue
        if skipping:
            continue
        if re.fullmatch(r'alias\s+cd=(?:z|"z"|\x27z\x27)\s*(?:#.*)?', value):
            continue
        # Remove only this installer's former generated zoxide alias.
        if re.fullmatch(r'if command -v z >/dev/null 2>&1; then alias cd=z; fi', value):
            continue
        for expression in ('zoxide init zsh', 'fzf --zsh', 'thefuck --alias'):
            old = 'eval "$(' + expression + ')"'
            if value == old:
                command = expression.split()[0]
                line = ('if command -v ' + command + ' >/dev/null 2>&1; then '
                        + old + '; fi\n')
        perl = 'eval "$(perl -I$HOME/perl5/lib/perl5 -Mlocal::lib=$HOME/perl5)"'
        if value == perl:
            line = ('if command -v perl >/dev/null 2>&1 && '
                    'perl -I"$HOME/perl5/lib/perl5" -Mlocal::lib -e 1 >/dev/null 2>&1; '
                    'then ' + perl + '; fi\n')
        output.append(line)
    if skipping:
        raise ValueError('Incomplete managed navigation block; preserving configuration')
    text = ''.join(output)
    # Quote the configured executable as shell data, never as shell code.
    quoted = "'" + str(brew).replace("'", "'\\''") + "'"
    block = (START + '\n# Initialise Homebrew before Oh My Zsh and package integrations.\n'
             'if [[ -x ' + quoted + ' ]]; then\n'
             '  eval "$(' + quoted + ' shellenv)"\nfi\n'
             '# Keep builtin cd; use z for zoxide directory jumps.\n' + END + '\n')
    marker = '### End Synology-Homebrew block\n'
    if marker in text:
        return text.replace(marker, marker + block, 1)
    return block + text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('zshrc', type=Path)
    parser.add_argument('--write', action='store_true')
    parser.add_argument('--brew', default='/home/linuxbrew/.linuxbrew/bin/brew')
    args = parser.parse_args()
    path = args.zshrc.expanduser().resolve(strict=True)
    original = path.read_bytes()
    revised = configure(original.decode('utf-8'), args.brew).encode('utf-8')
    if revised == original:
        print('Shell navigation is already configured.')
        return
    if not args.write:
        print('Plan: initialise Homebrew early and keep cd native; no files changed.')
        return
    zsh = shutil.which('zsh') or '/home/linuxbrew/.linuxbrew/bin/zsh'
    backup_dir = Path.home() / '.local/state/synology-homebrew/backups'
    backup_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix='.navigation-', dir=str(path.parent))
    try:
        with os.fdopen(descriptor, 'wb') as output:
            output.write(revised)
            os.fchmod(output.fileno(), path.stat().st_mode & 0o777)
        subprocess.run([zsh, '-n', temporary], check=True)
        if path.read_bytes() != original:
            raise RuntimeError('Shell configuration changed during preparation')
        stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
        fd, backup = tempfile.mkstemp(prefix='zshrc-navigation-' + stamp + '-', dir=str(backup_dir))
        with os.fdopen(fd, 'wb') as output:
            output.write(original)
        os.replace(temporary, str(path))
        print('Shell navigation fixed; original saved at ' + backup)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == '__main__':
    main()

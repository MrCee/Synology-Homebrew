#!/usr/bin/env python3
"""Complete the YAML-selected Neovim setup without compiling Homebrew formulas."""
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent


def run(args, **kwargs):
    subprocess.run([str(a) for a in args], check=True, **kwargs)


def main():
    config = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'config.yaml'
    data = json.loads(subprocess.check_output(['yq', '-o=json', '.', str(config)], text=True))
    if data.get('packages', {}).get('neovim', {}).get('action') != 'install':
        print('Neovim is not selected for installation; preserving existing configuration.')
        return
    run([sys.executable, ROOT/'install-macos-binaries.py', 'neovim', 'node'])
    plugin = data.get('plugins', {}).get('mrcee.nvim', {})
    if plugin.get('action') != 'install':
        print('Neovim configuration is not selected; keeping existing configuration.')
        return
    if os.environ.get('SYNOBREW_ALLOW_NVIM_BUILDS') != '1':
        if not sys.stdin.isatty() or input('Allow native Neovim plugin builds for the complete setup? [y/N] ').lower() != 'y':
            raise RuntimeError('Plugin setup requires explicit native-plugin build approval.')
    target = Path(plugin['directory']).expanduser()
    url = plugin['url']
    if target.exists():
        origin = subprocess.check_output(['git', '-C', str(target), 'remote', 'get-url', 'origin'], text=True).strip()
        if origin != url:
            raise RuntimeError('Existing Neovim configuration has a different origin; preserving it: ' + str(target))
        if subprocess.check_output(['git', '-C', str(target), 'status', '--porcelain'], text=True).strip():
            print('Preserving local configuration changes; not pulling over them.')
        else:
            run(['git', '-C', target, 'pull', '--ff-only'])
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        run(['git', 'clone', '--', url, target])
    # A separate app name protects an unrelated default configuration.
    env = dict(os.environ)
    if target != Path.home()/'.config/nvim':
        if target.parent != Path.home()/'.config':
            raise RuntimeError('Neovim configuration must be directly under ~/.config.')
        env['NVIM_APPNAME'] = target.name
    else:
        env.pop('NVIM_APPNAME', None)
    print('Installing Neovim plugins. Native plugin builds are enabled; Homebrew source builds stay blocked.', flush=True)
    run(['nvim', '--headless', '+Lazy! sync', '+qa'], env=env)
    run(['nvim', '--headless', '+TSUpdateSync', '+qa'], env=env)
    tool_script = json.dumps(str(ROOT/'neovim-install-tools.lua'))
    run(['nvim', '--headless', '-c', 'lua local ok,e=pcall(dofile,' + tool_script + '); if not ok then print(e); vim.cmd("cquit 1") end', '+qa'], env=env)
    run(['nvim', '--headless', '+lua print("Neovim configuration startup verified")',
         '+lua print(vim.g.clipboard and vim.g.clipboard.name or "normal-local-clipboard")', '+qa'], env=env)
    print('Complete: YAML-selected Neovim configuration and plugins.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError, KeyError, ValueError) as exc:
        sys.exit('Neovim setup failed: ' + str(exc))

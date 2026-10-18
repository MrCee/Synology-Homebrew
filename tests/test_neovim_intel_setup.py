import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('neovim_setup', ROOT/'setup-neovim-intel.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class NeovimSetupTests(unittest.TestCase):
    def test_yaml_selected_configuration_runs_full_plugin_setup(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            config = {'packages': {'neovim': {'action': 'install'}}, 'plugins': {'mrcee.nvim': {
                'action': 'install', 'directory': str(home/'.config/nvim'), 'url': 'https://example.test/config'}}}
            with patch.object(setup.Path, 'home', return_value=home), patch.object(sys, 'argv', ['setup', str(home/'config.yaml')]), patch.dict(os.environ, {'SYNOBREW_ALLOW_NVIM_BUILDS': '1'}), patch.object(setup.subprocess, 'check_output', return_value=json.dumps(config)), patch.object(setup, 'run') as run:
                setup.main()
                calls = [list(map(str, c.args[0])) for c in run.call_args_list]
                self.assertTrue(any(c[:2] == ['git', 'clone'] and c[-2:] == ['https://example.test/config', str(home/'.config/nvim')] for c in calls))
                self.assertTrue(any('+Lazy! sync' in c for c in calls))
                self.assertTrue(any('+TSUpdateSync' in c for c in calls))
                self.assertTrue(any('neovim-install-tools.lua' in ' '.join(c) for c in calls))
                self.assertFalse(any(c[0] == 'brew' for c in calls))

    def test_native_builds_need_explicit_approval(self):
        config = {'packages': {'neovim': {'action': 'install'}}, 'plugins': {'mrcee.nvim': {'action': 'install'}}}
        with patch.object(sys, 'argv', ['setup']), patch.dict(os.environ, {'SYNOBREW_ALLOW_NVIM_BUILDS': '0'}), patch.object(sys.stdin, 'isatty', return_value=False), patch.object(setup.subprocess, 'check_output', return_value=json.dumps(config)), patch.object(setup, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'approval'):
                setup.main()
            self.assertFalse(any(c.args[0][0] == 'nvim' for c in run.call_args_list))

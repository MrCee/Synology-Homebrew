import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("binary_brew", Path(__file__).resolve().parents[1] / "binary-brew.py")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class BrewEntryTest(unittest.TestCase):
    def test_install_routes_to_guarded_installer(self):
        command = guard.dispatch(["install", "--quiet", "jq", "node"])
        self.assertTrue(command[1].endswith("install-macos-binaries.py"))
        self.assertEqual(command[2:], ["jq", "node"])

    def test_source_build_and_unknown_options_are_refused(self):
        for flag in ["--build-from-source", "-s", "--HEAD", "--cask", "--ignore-dependencies"]:
            with self.subTest(flag=flag), self.assertRaises(ValueError):
                guard.dispatch(["install", flag, "jq"])

    def test_other_build_paths_are_refused(self):
        for command in ["upgrade", "reinstall", "bundle", "postinstall", "test"]:
            with self.subTest(command=command), self.assertRaises(ValueError):
                guard.dispatch([command])

    def test_read_commands_use_real_homebrew(self):
        self.assertEqual(guard.dispatch(["list", "--versions"]), [guard.REAL_BREW, "list", "--versions"])


if __name__ == "__main__":
    unittest.main()

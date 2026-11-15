"""Exercise packaging boundaries without building an app or mounting an image."""

import importlib.util
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SOURCE_ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("buckle_dmg", SOURCE_ROOT / "Scripts/create-dmg.py")
dmg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dmg)


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="buckle-package-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.app = self.root / "inputs/Buckle.app"
        (self.app / "Contents").mkdir(parents=True)
        self.manifest = {"version": "1.2.3", "build": 8, "packagingEnabled": True}
        self.info = {
            "CFBundleIdentifier": "studio.slippindylan.Buckle",
            "CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "8", "AppUpdaterEnabled": False,
        }
        self.write_info()
        root_patch = patch.object(dmg, "ROOT", self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)
        self.manifest_patch = patch.object(dmg, "read_manifest", return_value=self.manifest)
        self.manifest_patch.start()
        self.addCleanup(self.manifest_patch.stop)
        self.version_patch = patch.object(dmg, "version", return_value="1.6.7")
        self.version_patch.start()
        self.addCleanup(self.version_patch.stop)
        self.platform_patch = patch.object(dmg.sys, "platform", "darwin")
        self.platform_patch.start()
        self.addCleanup(self.platform_patch.stop)
        self.python_patch = patch.object(dmg.sys, "version_info", (3, 10))
        self.python_patch.start()
        self.addCleanup(self.python_patch.stop)
        self.run_patch = patch.object(dmg.subprocess, "run", side_effect=self.run_tool)
        self.run = self.run_patch.start()
        self.addCleanup(self.run_patch.stop)

    def write_info(self):
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(self.info))

    def run_tool(self, command, **kwargs):
        self.assertTrue(kwargs["check"])
        if command[0] == "bash":
            self.assertEqual(command, ["bash", str(self.root / "Scripts/verify-bundle.sh"), "--distribution", str(self.app)])
        else:
            self.assertEqual(command[:3], [dmg.sys.executable, "-m", "dmgbuild"])
            self.assertIn("app=" + str(self.app), command)
            Path(command[-1]).write_bytes(b"new installer")

    def test_disabled_packaging_stops_before_app_or_platform_inspection(self):
        self.manifest["packagingEnabled"] = False
        with self.assertRaisesRegex(ValueError, "Packaging is disabled"):
            dmg.package(self.root / "missing.app")
        self.run.assert_not_called()
        self.assertFalse((self.root / "build").exists())

    def test_wrong_identity_version_or_build_cannot_be_packaged(self):
        for key, value in (("CFBundleIdentifier", "other.Buckle"), ("CFBundleShortVersionString", "1.2.2"), ("CFBundleVersion", "7")):
            original = self.info[key]
            self.info[key] = value
            self.write_info()
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "does not match"):
                dmg.package(self.app)
            self.info[key] = original
        self.run.assert_not_called()

    def test_test_packages_require_an_explicit_disabled_updater(self):
        for value in (None, True, "YES", 0, 1, "false"):
            self.info.pop("AppUpdaterEnabled", None)
            if value is not None:
                self.info["AppUpdaterEnabled"] = value
            self.write_info()
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "AppUpdaterEnabled"):
                dmg.package(self.app)
        self.run.assert_not_called()
        for value in (False, "NO"):
            self.info["AppUpdaterEnabled"] = value
            self.write_info()
            output = dmg.package(self.app)
            self.assertEqual(output, self.root / "build/Buckle-1.2.3-8-test.dmg")
            self.assertEqual(output.read_bytes(), b"new installer")
            output.unlink()

    def test_releases_require_an_explicit_enabled_updater(self):
        with self.assertRaisesRegex(ValueError, "AppUpdaterEnabled"):
            dmg.package(self.app, release=True)
        for value in (True, "YES"):
            self.info["AppUpdaterEnabled"] = value
            self.write_info()
            output = dmg.package(self.app, release=True)
            self.assertEqual(output, self.root / "build/Buckle-1.2.3.dmg")
            output.unlink()

    def test_output_is_confined_to_build_and_existing_files_are_preserved(self):
        for output in (self.root / "installer.dmg", "build/../installer.dmg", "build/installer.zip"):
            with self.subTest(output=str(output)), self.assertRaisesRegex(ValueError, "(build|traversal)"):
                dmg.package(self.app, output)
        existing = self.root / "build/existing.dmg"
        existing.parent.mkdir()
        existing.write_bytes(b"existing installer")
        with self.assertRaisesRegex(ValueError, "overwrite"):
            dmg.package(self.app, existing)
        self.assertEqual(existing.read_bytes(), b"existing installer")
        self.run.assert_not_called()

    def test_redirected_build_and_nested_or_dangling_symlinks_are_rejected(self):
        outside = self.root / "outside"
        outside.mkdir()
        build = self.root / "build"
        build.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "redirect"):
            dmg.package(self.app)
        build.unlink()
        build.mkdir()
        redirected = build / "nested"
        redirected.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symbolic"):
            dmg.package(self.app, redirected / "installer.dmg")
        dangling = build / "dangling.dmg"
        dangling.symlink_to(outside / "missing.dmg")
        with self.assertRaisesRegex(ValueError, "symbolic"):
            dmg.package(self.app, dangling)
        self.assertEqual(list(outside.iterdir()), [])
        self.run.assert_not_called()

    def test_distribution_validation_failure_stops_before_dmgbuild(self):
        self.run.side_effect = subprocess.CalledProcessError(1, ["verify-bundle"])
        with self.assertRaises(subprocess.CalledProcessError):
            dmg.package(self.app)
        self.assertEqual(self.run.call_count, 1)
        self.assertFalse((self.root / "build").exists())

    def test_tool_version_is_pinned_and_python_requirement_is_explicit(self):
        with patch.object(dmg, "version", return_value="1.6.6"), self.assertRaisesRegex(ValueError, "1.6.7"):
            dmg.package(self.app)
        with patch.object(dmg.sys, "version_info", (3, 9)), self.assertRaisesRegex(ValueError, "Python 3.10"):
            dmg.package(self.app)
        self.assertFalse((self.root / "build").exists())

    def test_failed_dmgbuild_does_not_publish_and_only_its_staging_is_removed(self):
        def fail(command, **kwargs):
            if command[0] != "bash":
                Path(command[-1]).write_bytes(b"partial installer")
                raise subprocess.CalledProcessError(1, command)
        self.run.side_effect = fail
        with self.assertRaises(subprocess.CalledProcessError):
            dmg.package(self.app)
        self.assertEqual(list((self.root / "build").iterdir()), [])

    def test_concurrent_output_creation_is_not_overwritten(self):
        output = self.root / "build/installer.dmg"
        def race(command, **kwargs):
            self.run_tool(command, **kwargs)
            if command[0] != "bash":
                output.write_bytes(b"another installer")
        self.run.side_effect = race
        with self.assertRaises(FileExistsError):
            dmg.package(self.app, output)
        self.assertEqual(output.read_bytes(), b"another installer")
        self.assertEqual(list(output.parent.iterdir()), [output])


if __name__ == "__main__":
    unittest.main()

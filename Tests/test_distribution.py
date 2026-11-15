import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / 'Scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


preflight = load('release-preflight')
distribution = load('distribution')


class ReleasePreflightTests(unittest.TestCase):
    def test_version_and_build_must_both_increase(self):
        previous = [{'version': '0.2.0', 'build': 4}, {'version': '0.1.0', 'build': 1}]
        preflight.validate_transition({'version': '0.3.0', 'build': 5}, previous)
        for version, build in [('0.3.0', 4), ('0.2.0', 5), ('0.1.9', 6), ('0.0.1', 1)]:
            with self.subTest(version=version, build=build), self.assertRaises(ValueError):
                preflight.validate_transition({'version': version, 'build': build}, previous)

    def test_preflight_reads_all_stable_release_manifests(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'Config/Release').mkdir(parents=True)
            (root / 'Config/Release/manifest.json').write_text(json.dumps(
                {'version': '0.3.0', 'build': 4, 'packagingEnabled': True}))
            releases = [[{'tag_name': 'v0.1.0', 'draft': False, 'prerelease': False},
                         {'tag_name': 'v9.0.0', 'draft': True, 'prerelease': False}],
                        [{'tag_name': 'v0.2.0', 'draft': False, 'prerelease': False}]]
            def encoded(version, build):
                return {'content': base64.b64encode(json.dumps({'version': version, 'build': build}).encode()).decode()}
            with patch.object(preflight, 'ROOT', root), patch.dict('os.environ', {'GITHUB_REPOSITORY': 'owner/Buckle'}), \
                 patch.object(preflight, 'gh', side_effect=[releases, encoded('0.1.0', 1), encoded('0.2.0', 4)]) as gh:
                with self.assertRaisesRegex(ValueError, 'must increase'):
                    preflight.main()
                self.assertEqual(gh.call_count, 3)

    def test_invalid_manifest_is_not_a_first_release(self):
        for value in [{'version': '0.3', 'build': 1}, {'version': '0.3.0', 'build': True},
                      {'version': '0.3.0', 'build': 0}]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                preflight.validate_transition(value, [])


class CaskTests(unittest.TestCase):
    def test_cask_uses_matching_public_asset_hash_and_preserves_other_apps(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / 'Buckle-0.2.0.dmg'
            archive.write_bytes(b'installer')
            release = {'tagName': 'v0.2.0', 'isDraft': False, 'isPrerelease': False, 'assets': [
                {'name': archive.name, 'size': 9,
                 'url': 'https://github.com/SlippinDylan/Buckle/releases/download/v0.2.0/Buckle-0.2.0.dmg'}]}
            text = distribution.cask(release, '0.2.0', archive)
            self.assertIn(hashlib.sha256(b'installer').hexdigest(), text)
            self.assertIn('depends_on macos: ">= :sequoia"', text)
            for key in ['isDraft', 'isPrerelease']:
                with self.subTest(key=key), self.assertRaises(ValueError):
                    distribution.cask({**release, key: True}, '0.2.0', archive)
            with self.assertRaises(ValueError):
                distribution.cask(release, '0.3.0', archive)
            release['assets'][0]['url'] = 'https://example.test/fake.dmg'
            with self.assertRaises(ValueError):
                distribution.cask(release, '0.2.0', archive)
        original = '# Tap\n\n| Application | Cask | Status |\n|---|---|---|\n| Other | `other` | Available |\n'
        updated = distribution.update_readme(original)
        self.assertIn('| Other | `other` | Available |', updated)
        self.assertEqual(distribution.update_readme(updated), updated)
        self.assertIn('brew install --cask slippindylan/tap/buckle', updated)
        with self.assertRaises(ValueError):
            distribution.update_readme('# Changed table layout')


    def test_cask_cannot_downgrade_or_replace_published_identity(self):
        current = 'cask "buckle" do\n  version "0.3.0"\n  sha256 "original"\nend\n'
        distribution.validate_cask_transition(current, '0.3.0', current)
        distribution.validate_cask_transition(current, '0.4.0', 'new version')
        for version, text in [('0.2.0', 'older'), ('0.3.0', 'changed hash')]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                distribution.validate_cask_transition(current, version, text)


    def test_tap_symlinks_cannot_redirect_writes_into_other_apps(self):
        with tempfile.TemporaryDirectory() as temporary:
            tap = Path(temporary) / 'tap'
            (tap / 'Casks').mkdir(parents=True)
            other = tap / 'Casks/other.rb'
            other.write_text('other app')
            link = tap / 'Casks/buckle.rb'
            link.symlink_to(other)
            with self.assertRaises(ValueError):
                distribution.validate_tap_paths(tap)
            self.assertEqual(other.read_text(), 'other app')
            link.unlink()
            (tap / 'README.md').symlink_to(other)
            with self.assertRaises(ValueError):
                distribution.validate_tap_paths(tap)


class WorkflowBoundaryTests(unittest.TestCase):
    def test_only_manual_workflows_can_package_or_publish(self):
        ci = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertNotIn('gh release create', ci)
        self.assertNotIn('create-dmg', ci)
        self.assertIn("if: needs.baseline.outputs.has_app == 'true' && needs.baseline.outputs.build == 'true'", ci)
        package = (ROOT / '.github/workflows/package.yml').read_text()
        self.assertIn('APP_UPDATER_ENABLED=NO', package)
        self.assertNotIn('gh release create', package)
        self.assertNotIn('SPARKLE_ED_PRIVATE_KEY', package)
        release = (ROOT / '.github/workflows/release.yml').read_text()
        self.assertLess(release.index('update-key.mjs'), release.index('APP_UPDATER_ENABLED=YES'))
        self.assertLess(release.index('Scripts/release-preflight.py'), release.index('gh release create'))
        for workflow in (package, release):
            self.assertIn('workflow_dispatch:', workflow)
            self.assertNotIn('\n  push:', workflow)
            self.assertIn('Scripts/require-ci.py', workflow)


if __name__ == '__main__':
    unittest.main()

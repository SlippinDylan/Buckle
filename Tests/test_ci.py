import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'Scripts'


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), SCRIPTS / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


changes = load('ci-changes')
required_ci = load('require-ci')


class CIClassificationTests(unittest.TestCase):
    def test_documentation_and_local_settings_do_not_build(self):
        paths = ['README.md', 'README.zh-CN.md', 'docs/development.md',
                 'docs/images/readme/example.png', 'AGENTS.md', 'App/AGENTS.md',
                 '.gitignore', '.editorconfig', '.vscode/settings.json', 'LICENSE']
        self.assertEqual(changes.classify(paths), {'build': False, 'baseline': False, 'notifications': False})

    def test_infrastructure_runs_checks_without_building_app(self):
        for path in ('CHANGELOG.md', '.github/workflows/ci.yml', '.github/workflows/package.yml',
                     'Scripts/create-dmg.py', '.github/scripts/release-notes.mjs', 'Scripts/release-preflight.py',
                     'Scripts/distribution.py', 'Tests/test_distribution.py', 'Config/DMG/settings.py'):
            with self.subTest(path=path):
                self.assertEqual(changes.classify([path]), {'build': False, 'baseline': True, 'notifications': False})
        self.assertEqual(changes.classify(['.github/scripts/discord-notify.mjs']),
                         {'build': False, 'baseline': True, 'notifications': True})

    def test_app_inputs_unknown_paths_and_mixed_changes_build(self):
        for path in ('App/Main.swift', 'App/Help.md', 'App/Localizable.xcstrings', 'Example.icon/icon.json',
                     'Example.xcodeproj/project.pbxproj', 'Config/Debug.xcconfig', 'Config/Generated/Version.xcconfig',
                     'Info.plist', 'App.entitlements', 'Package.resolved', '.gitattributes', 'Tests/ExampleTests.swift',
                     'Scripts/build-assets.py', '.github/scripts/build-resources.py', 'new-folder/input.json'):
            with self.subTest(path=path):
                self.assertTrue(changes.classify(['README.md', path])['build'])

    def test_manual_and_first_push_request_full_validation(self):
        for event_name, event in (('workflow_dispatch', {}), ('push', {'before': '0' * 40, 'after': 'abc'})):
            self.assertEqual(changes.plan(event_name, event), {'build': True, 'baseline': True, 'notifications': True})
        with self.assertRaises(ValueError):
            changes.plan('issues', {})

    def test_real_git_diffs_handle_switch_versions_deletions_and_renames(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            def git(*args):
                return subprocess.run(['git', *args], cwd=root, check=True, capture_output=True, text=True).stdout.strip()
            git('init', '-q')
            git('config', 'user.name', 'CI test')
            git('config', 'user.email', 'ci-test@example.invalid')
            def commit():
                git('add', '.')
                git('commit', '-qm', 'fixture')
                return git('rev-parse', 'HEAD')
            manifest = root / changes.MANIFEST
            manifest.parent.mkdir(parents=True)
            data = {'version': '0.1.0', 'build': 1, 'packagingEnabled': False}
            manifest.write_text(json.dumps(data))
            (root / 'docs').mkdir()
            (root / 'docs/help.md').write_text('Help text\n')
            before = commit()
            with patch.object(changes, 'ROOT', root):
                data['packagingEnabled'] = True
                manifest.write_text(json.dumps(data))
                after = commit()
                result = changes.plan('push', {'before': before, 'after': after})
                self.assertTrue(result['build'])
                self.assertTrue(result['baseline'])
                before = after
                data['packagingEnabled'] = False
                manifest.write_text(json.dumps(data))
                after = commit()
                self.assertFalse(changes.plan('push', {'before': before, 'after': after})['build'])
                before = after
                manifest.write_text(json.dumps(data, indent=2))
                after = commit()
                self.assertFalse(changes.plan('push', {'before': before, 'after': after})['build'])
                before = after
                data['version'] = '0.2.0'
                manifest.write_text(json.dumps(data))
                after = commit()
                self.assertTrue(changes.plan('push', {'before': before, 'after': after})['build'])
                before = after
                (root / 'Resources').mkdir()
                git('mv', 'docs/help.md', 'Resources/help.md')
                after = commit()
                self.assertTrue(changes.plan('push', {'before': before, 'after': after})['build'])
                before = after
                (root / 'Resources/help.md').unlink()
                after = commit()
                self.assertTrue(changes.plan('push', {'before': before, 'after': after})['build'])
                before = after
                (root / 'README.md').write_text('Docs only\n')
                after = commit()
                self.assertFalse(changes.plan('push', {'before': before, 'after': after})['build'])
                with self.assertRaises(subprocess.CalledProcessError):
                    changes.plan('push', {'before': 'f' * 40, 'after': after})

    def test_pull_request_uses_merge_base_not_new_base_branch_changes(self):
        with patch.object(changes, 'git', side_effect=[b'mergebase\n', b'docs/help.md\0']) as git:
            result = changes.plan('pull_request', {'pull_request': {'base': {'sha': 'base'}, 'head': {'sha': 'head'}}})
        self.assertFalse(result['build'])
        self.assertEqual(git.call_args.args, ('diff', '--name-only', '--no-renames', '-z', 'mergebase', 'head'))


class PackagingCIGateTests(unittest.TestCase):
    def run_data(self, event='push', conclusion='success', sha='current', run_id=1):
        return {'event': event, 'conclusion': conclusion, 'headSha': sha, 'databaseId': run_id}

    def test_latest_exact_commit_push_or_manual_run_must_succeed(self):
        for event in ('push', 'workflow_dispatch'):
            self.assertEqual(required_ci.select_run([self.run_data(event)], 'current'), 1)
        for runs in ([], [self.run_data(sha='older')], [self.run_data(event='pull_request')],
                     [self.run_data(conclusion=None), self.run_data()],
                     [self.run_data(conclusion='failure'), self.run_data()]):
            with self.subTest(runs=runs), self.assertRaises(ValueError):
                required_ci.select_run(runs, 'current')

    def test_automatic_release_uses_its_triggering_ci_even_when_a_newer_run_is_in_progress(self):
        runs = [self.run_data(conclusion=None, run_id=2), self.run_data(run_id=1)]
        self.assertEqual(required_ci.select_run(runs, 'current', source_run_id=1), 1)
        with self.assertRaises(ValueError):
            required_ci.select_run(runs, 'current')
        with self.assertRaises(ValueError):
            required_ci.select_run(runs, 'current', source_run_id=3)
        with self.assertRaises(ValueError):
            required_ci.select_run(runs, 'other', source_run_id=1)

    def test_automatic_release_reports_skipped_build_without_treating_it_as_success(self):
        body = {'total_count': 1, 'jobs': [{'name': 'Build Debug app', 'conclusion': 'skipped'}]}
        self.assertFalse(required_ci.build_succeeded(body))
        with self.assertRaises(ValueError):
            required_ci.check_jobs(body)
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / 'outputs'
            with patch.dict('os.environ', {'GITHUB_REPOSITORY': 'owner/Example', 'GITHUB_SHA': 'default',
                                          'RELEASE_SHA': 'source', 'GITHUB_OUTPUT': str(output)}), \
                 patch.object(required_ci, 'gh', side_effect=[[self.run_data(sha='source')], {'run_attempt': 2}, body]) as gh:
                required_ci.main(allow_skipped=True)
            self.assertEqual(output.read_text(), 'build=false\n')
            self.assertIn('source', gh.call_args_list[0].args)

    def test_skipped_missing_duplicate_and_wrong_attempt_builds_do_not_pass(self):
        required_ci.check_jobs({'total_count': 2, 'jobs': [{'name': 'baseline', 'conclusion': 'success'},
                                                         {'name': 'Build Debug app', 'conclusion': 'success'}]})
        for jobs in ([], [{'name': 'Build Debug app', 'conclusion': 'skipped'}],
                     [{'name': 'Build Debug app', 'conclusion': 'failure'}],
                     [{'name': 'Build Debug app', 'conclusion': 'success'}] * 2):
            with self.subTest(jobs=jobs), self.assertRaises(ValueError):
                required_ci.check_jobs({'total_count': len(jobs), 'jobs': jobs})
        with self.assertRaises(ValueError):
            required_ci.check_jobs({'total_count': 101, 'jobs': [{'name': 'Build Debug app', 'conclusion': 'success'}]})
        with patch.dict('os.environ', {'GITHUB_REPOSITORY': 'owner/Example', 'GITHUB_SHA': 'current'}), \
             patch.object(required_ci, 'gh', side_effect=[[self.run_data()], {'run_attempt': 3},
                           {'total_count': 1, 'jobs': [{'name': 'Build Debug app', 'conclusion': 'success'}]}]) as gh:
            required_ci.main()
        self.assertIn('/attempts/3/jobs?', gh.call_args.args[1])


class RequiredStatusTests(unittest.TestCase):
    def test_required_check_rejects_failed_or_unexpectedly_skipped_builds(self):
        workflow = (ROOT / '.github/workflows/ci.yml').read_text()
        job = workflow.split('\n  check:\n', 1)[1]
        self.assertIn('needs: [baseline, build]', job)
        self.assertIn('if: always()', job)
        script = job.split('        run: |\n', 1)[1].split('\n      - ', 1)[0]
        script = '\n'.join(line[10:] for line in script.splitlines())
        for baseline, required, build, success in [
            ('success', 'true', 'success', True),
            ('success', 'false', 'skipped', True),
            ('failure', 'false', 'skipped', False),
            ('success', 'true', 'failure', False),
            ('success', 'true', 'skipped', False),
            ('success', 'true', 'cancelled', False),
            ('success', '', 'skipped', False),
        ]:
            with self.subTest(baseline=baseline, required=required, build=build):
                result = subprocess.run(['bash', '-e', '-c', script], capture_output=True,
                                        env={'BASELINE_RESULT': baseline, 'BUILD_REQUIRED': required,
                                             'BUILD_RESULT': build})
                self.assertEqual(result.returncode == 0, success)


if __name__ == '__main__':
    unittest.main()

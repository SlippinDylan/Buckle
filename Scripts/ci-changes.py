#!/usr/bin/env python3
"""Classify GitHub changes before deciding whether to build the app."""

import json
import os
from pathlib import Path, PurePosixPath
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = 'Config/Release/manifest.json'


def classify(paths, switch_only=False):
    result = {'build': False, 'baseline': False, 'notifications': False}
    for name in paths:
        path = PurePosixPath(name)
        if name == MANIFEST and switch_only:
            result['baseline'] = True
        elif path.name == 'AGENTS.md' or name in ('.gitignore', '.editorconfig', 'LICENSE', 'LICENSE.md'):
            continue
        elif name.startswith(('.vscode/', '.idea/')):
            continue
        elif path.parent == PurePosixPath('.') and (path.name == 'README.md' or path.name.startswith('README.') and path.suffix == '.md'):
            continue
        elif name.startswith('docs/') and (path.suffix == '.md' or name.startswith('docs/images/readme/')):
            continue
        elif name == 'CHANGELOG.md':
            result['baseline'] = True
        elif (name.startswith(('.github/workflows/', '.github/ISSUE_TEMPLATE/'))
              or name in {'.github/scripts/' + stem + suffix
                          for stem in ('discord-notify', 'plan-release', 'release-notes', 'sync-version',
                                       'update-key', 'update-tools', 'verify-bundle')
                          for suffix in ('.mjs', '.test.mjs')}
              or name in ('.github/PULL_REQUEST_TEMPLATE.md', '.github/CODEOWNERS')):
            result['baseline'] = True
            result['notifications'] |= name == '.github/scripts/discord-notify.mjs'
        elif name in ('Scripts/check.py', 'Scripts/check-localizations.py', 'Scripts/sync-version.py',
                      'Scripts/release-notes.py', 'Scripts/ci-changes.py', 'Scripts/require-ci.py',
                      'Scripts/create-dmg.py', 'Scripts/create-dmg.sh', 'Scripts/prepare-update.sh',
                      'Scripts/update_feed.py', 'Scripts/release-preflight.py', 'Scripts/distribution.py') or name == 'Config/standards.json' or name.startswith('Config/DMG/') or (name.startswith('Tests/test_') and name.endswith('.py')):
            result['baseline'] = True
        else:
            # Unknown paths may be app resources, dependencies or build-phase inputs.
            result['build'] = True
            result['baseline'] = True
    return result


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, check=True, capture_output=True).stdout


def plan(event_name, event):
    if event_name == 'workflow_dispatch':
        return {'build': True, 'baseline': True, 'notifications': True}
    if event_name == 'push':
        before, after = event['before'], event['after']
        if before == '0' * 40:
            return {'build': True, 'baseline': True, 'notifications': True}
        comparison = (before, after)
    elif event_name == 'pull_request':
        before = event['pull_request']['base']['sha']
        after = event['pull_request']['head']['sha']
        before = git('merge-base', before, after).decode().strip()
        comparison = (before, after)
    else:
        raise ValueError('Unsupported CI event: ' + event_name)
    paths = git('diff', '--name-only', '--no-renames', '-z', *comparison).decode().rstrip('\0').split('\0')
    paths = [path for path in paths if path]
    switch_only = False
    if MANIFEST in paths:
        try:
            old = json.loads(git('show', before + ':' + MANIFEST))
            new = json.loads(git('show', after + ':' + MANIFEST))
        except (subprocess.CalledProcessError, ValueError):
            pass  # A new or invalid manifest requires a build and baseline validation.
        else:
            switch_only = (isinstance(old, dict) and isinstance(new, dict)
                           and set(old) == set(new) == {'version', 'build', 'packagingEnabled'}
                           and type(old['packagingEnabled']) is bool and type(new['packagingEnabled']) is bool
                           and old['version'] == new['version'] and old['build'] == new['build']
                           and not (old['packagingEnabled'] is False and new['packagingEnabled'] is True))
    return classify(paths, switch_only)


def main():
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    result = plan(os.environ['GITHUB_EVENT_NAME'], event)
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for name, enabled in result.items():
            output.write(name + '=' + str(enabled).lower() + '\n')
    print('CI plan: ' + json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))

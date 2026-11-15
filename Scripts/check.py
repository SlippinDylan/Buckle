#!/usr/bin/env python3
"""Validate the engineering baseline without compiling or starting Buckle."""

import ast
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    os.chdir(ROOT)
    os.environ['PYTHONDONTWRITEBYTECODE'] = '1'
    metadata = json.loads((ROOT / 'Config/standards.json').read_text())
    if metadata['appName'] != 'Buckle' or metadata['bundleIdentifier'] != 'studio.slippindylan.Buckle':
        raise ValueError('Standards metadata must retain Buckle identity')
    for path in ('AGENTS.md', '.gitignore', 'docs/development.md', 'docs/development-cleanup.md',
                 'docs/setup-status.md', 'Buckle.icon/icon.json',
                 'Buckle.xcodeproj/xcshareddata/xcschemes/Buckle.xcscheme'):
        if not (ROOT / path).is_file():
            raise ValueError('Missing baseline input: ' + path)
    for directory in ('Scripts', 'Config/DMG', 'Tests'):
        for path in (ROOT / directory).rglob('*.py'):
            ast.parse(path.read_text(), filename=str(path))
    subprocess.run(['node', '.github/scripts/sync-version.mjs', '--check'], check=True)
    subprocess.run(['node', '.github/scripts/release-notes.mjs', '--check'], check=True)
    subprocess.run([sys.executable, '-B', 'Scripts/check-localizations.py'], check=True)
    subprocess.run([sys.executable, '-B', '-m', 'unittest', 'discover', '-s', 'Tests', '-p', 'test_*.py'], check=True)
    subprocess.run(['node', '--test', *map(str, sorted(Path('.github/scripts').glob('*.test.mjs')))], check=True)
    for script in Path('Scripts').glob('*.sh'):
        subprocess.run(['bash', '-n', str(script)], check=True)
    subprocess.run(['git', 'diff', '--check'], check=True)
    print('Engineering baseline passed; no application was compiled or launched.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, SyntaxError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))

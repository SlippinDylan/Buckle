#!/usr/bin/env python3
"""Reject non-increasing releases before building or publishing an installer."""

import base64
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]


def identity(manifest):
    version, build = manifest['version'], manifest['build']
    if not isinstance(version, str) or not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version):
        raise ValueError('Expected a three-part release version')
    if type(build) is not int or build <= 0:
        raise ValueError('Expected a positive release build')
    return tuple(map(int, version.split('.'))), build


def validate_transition(current, published):
    version, build = identity(current)
    for previous in published:
        old_version, old_build = identity(previous)
        if version <= old_version or build <= old_build:
            raise ValueError('Both version and build must increase beyond every published stable release')


def gh(*arguments):
    return json.loads(subprocess.run(['gh', *arguments], check=True, capture_output=True, text=True).stdout)


def main():
    current = json.loads((ROOT / 'Config/Release/manifest.json').read_text())
    if current['packagingEnabled'] is not True:
        raise ValueError('Enable packaging explicitly before requesting a release')
    repo = os.environ['GITHUB_REPOSITORY']
    pages = gh('api', '--paginate', '--slurp', 'repos/' + repo + '/releases?per_page=100')
    published = []
    for page in pages:
        for release in page:
            if release['draft'] or release['prerelease']:
                continue
            tag = release['tag_name']
            metadata = gh('api', 'repos/' + repo + '/contents/Config/Release/manifest.json?ref=' + quote(tag, safe=''))
            previous = json.loads(base64.b64decode(metadata['content'], validate=False))
            if tag != 'v' + previous['version']:
                raise ValueError('Published release tag does not match its manifest: ' + tag)
            published.append(previous)
    validate_transition(current, published)
    print('Version and build increase beyond all published stable releases.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))

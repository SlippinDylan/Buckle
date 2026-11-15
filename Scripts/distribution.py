#!/usr/bin/env python3
"""Generate Buckle's Cask from a downloaded, public, stable Release artifact."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

REPOSITORY = 'SlippinDylan/Buckle'


def cask(release, version, archive):
    if release['isDraft'] or release['isPrerelease'] or release['tagName'] != 'v' + version:
        raise ValueError('Expected the matching published stable release')
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version):
        raise ValueError('Invalid Cask version')
    url = 'https://github.com/' + REPOSITORY + '/releases/download/v' + version + '/Buckle-' + version + '.dmg'
    assets = [asset for asset in release['assets'] if asset['name'] == archive.name]
    if len(assets) != 1 or archive.name != 'Buckle-' + version + '.dmg' or assets[0]['url'] != url:
        raise ValueError('Cask must reference the actual public release installer')
    if archive.stat().st_size != assets[0]['size']:
        raise ValueError('Downloaded installer size does not match the release asset')
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    return '''cask "buckle" do
  version "%s"
  sha256 "%s"

  url "https://github.com/SlippinDylan/Buckle/releases/download/v#{version}/Buckle-#{version}.dmg"
  name "Buckle"
  desc "Menu-bar shortcuts for macOS and Finder"
  homepage "https://github.com/SlippinDylan/Buckle"

  auto_updates true
  depends_on macos: ">= :sequoia"

  app "Buckle.app"
end
''' % (version, digest)


def validate_cask_transition(existing, version, candidate):
    match = re.search(r'^  version "([0-9]+\.[0-9]+\.[0-9]+)"$', existing, re.MULTILINE)
    if not match:
        raise ValueError('Existing Buckle Cask has no explicit stable version')
    old = tuple(map(int, match.group(1).split('.')))
    new = tuple(map(int, version.split('.')))
    if new < old or (new == old and existing != candidate):
        raise ValueError('Cannot downgrade or replace an existing version of the Buckle Cask')


def update_readme(text):
    row = '| Buckle | `buckle` | Available: `brew install --cask slippindylan/tap/buckle` |'
    if re.search(r'^\| Buckle \|', text, re.MULTILINE):
        return re.sub(r'^\| Buckle \|.*$', row, text, flags=re.MULTILINE)
    marker = '| Application | Cask | Status |\n|---|---|---|'
    if marker not in text:
        raise ValueError('Tap README application table changed; review it before syncing')
    return text.replace(marker, marker + '\n' + row, 1)


def validate_tap_paths(tap):
    if tap.is_symlink() or (tap / 'Casks').is_symlink():
        raise ValueError('Tap and Casks directories must not be symbolic links')
    for path in (tap / 'README.md', tap / 'Casks/buckle.rb'):
        if path.is_symlink():
            raise ValueError('Distribution metadata must not overwrite symbolic links: ' + str(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('tap', type=Path)
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    visibility = subprocess.run(['gh', 'repo', 'view', REPOSITORY, '--json', 'visibility'],
                                check=True, capture_output=True, text=True)
    if json.loads(visibility.stdout)['visibility'] != 'PUBLIC':
        raise ValueError('Homebrew installers must be publicly downloadable')
    result = subprocess.run(['gh', 'release', 'view', 'v' + args.version, '--repo', REPOSITORY,
                             '--json', 'tagName,isDraft,isPrerelease,assets'],
                            check=True, capture_output=True, text=True)
    validate_tap_paths(args.tap)
    content = cask(json.loads(result.stdout), args.version, args.archive)
    readme = args.tap / 'README.md'
    updated = update_readme(readme.read_text())
    directory = args.tap / 'Casks'
    directory.mkdir(exist_ok=True)
    destination = directory / 'buckle.rb'
    if destination.exists():
        validate_cask_transition(destination.read_text(), args.version, content)
    destination.write_text(content)
    readme.write_text(updated)


if __name__ == '__main__':
    main()

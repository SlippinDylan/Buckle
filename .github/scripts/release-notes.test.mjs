import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { extractReleaseNotes } from './release-notes.mjs';

const current = '## [1.2.0] - 2026-11-14\n\n### Fixed\n- Fixed a startup issue.';
const source = `# Changelog\n\n## [Unreleased]\n\n### Added\n- Future feature.\n\n${current}\n\n## [1.1.0] - 2026-10-01\n\n### Added\n- Older feature.\n`;

test('extracts only the requested version and preserves Markdown for both release consumers', () => {
  assert.equal(extractReleaseNotes(source, '1.2.0', 'v1.2.0'), `${current}\n`);
  assert.equal(extractReleaseNotes(source.replaceAll('\n', '\r\n'), '1.2.0'), `${current}\n`);
  assert.match(extractReleaseNotes(source, '1.1.0'), /Older feature/);
});

test('rejects missing, duplicate, empty, malformed or unfinished release metadata', () => {
  for (const invalid of [
    source.replace(current, ''),
    `${source}\n${current}`,
    source.replace('## [1.1.0]', '## [1.2.0]'),
    source.replace('## [Unreleased]', '## [Future]'),
    source.replace(' - 2026-11-14', ''),
    source.replace('2026-11-14', '2026-02-30'),
    source.replace('### Fixed\n- Fixed a startup issue.', ''),
    source.replace('- Fixed a startup issue.', '- '),
    source.replace('- Fixed a startup issue.', '- TODO: write notes.'),
    source.replace('### Fixed', '### 修复'),
    source.replace('- Fixed a startup issue.', 'Not a bullet.'),
    source.replace('### Fixed', '### Added\n\n### Fixed'),
    source.replace('- Fixed a startup issue.', '- Fixed a startup issue.\n\n### Fixed\n- Duplicate.'),
    source.replace('- Fixed a startup issue.', '- Fixed a startup issue.\n\n### Added'),
  ]) {
    assert.throws(() => extractReleaseNotes(invalid, '1.2.0'));
  }
  assert.throws(() => extractReleaseNotes(source, '1.2.0', 'v1.1.0'), /tag must match/);
});

test('CLI validates the selected source manifest and does not overwrite output on failure', async () => {
  const root = await mkdtemp(join(tmpdir(), 'buckle-notes-'));
  try {
    await mkdir(join(root, 'Config/Release'), { recursive: true });
    await writeFile(join(root, 'Config/Release/manifest.json'), JSON.stringify({ version: '1.2.0', build: 3, packagingEnabled: true }));
    await writeFile(join(root, 'CHANGELOG.md'), source);
    const output = join(root, 'notes.md');
    const invoke = (...args) => spawnSync(process.execPath, ['.github/scripts/release-notes.mjs', '--root', root, ...args], { encoding: 'utf8' });
    assert.equal(invoke('--check', '--tag', 'v1.2.0').status, 0);
    assert.equal(invoke('--output', output, '--tag', 'v1.2.0').status, 0);
    assert.equal(await readFile(output, 'utf8'), `${current}\n`);
    assert.notEqual(invoke('--tag', 'v1.1.0', '--output', output).status, 0);
    assert.equal(await readFile(output, 'utf8'), `${current}\n`);
    await rm(join(root, 'CHANGELOG.md'));
    assert.notEqual(invoke('--check').status, 0);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';
import { readReleaseManifest } from './sync-version.mjs';

export function extractReleaseNotes(source, version, tag = `v${version}`) {
  assert.equal(tag, `v${version}`, 'Release tag must match the manifest version.');
  const lines = source.replace(/\r\n/g, '\n').split('\n');
  assert.equal(lines[0], '# Changelog', 'Expected # Changelog.');
  const sections = new Map();
  let current;
  for (const line of lines.slice(1)) {
    if (line.startsWith('## ')) {
      const heading = /^## \[(Unreleased|(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))\](?: - (\d{4}-\d{2}-\d{2}))?$/.exec(line);
      assert.ok(heading, `Invalid changelog heading: ${line}`);
      const [, name, date] = heading;
      assert.ok(!sections.has(name), `Duplicate changelog version: ${name}`);
      if (name === 'Unreleased') {
        assert.ok(!date && sections.size === 0, 'Unreleased must be first and have no date.');
      } else {
        assert.ok(date && !Number.isNaN(Date.parse(date)) && new Date(date).toISOString().slice(0, 10) === date,
          `Version ${name} requires a valid YYYY-MM-DD date.`);
      }
      current = { heading: line, lines: [] };
      sections.set(name, current);
    } else if (current) {
      current.lines.push(line);
    } else {
      assert.ok(!line.trim(), 'Unexpected text before Unreleased.');
    }
  }
  assert.ok(sections.has('Unreleased'), 'Missing Unreleased section.');
  const release = sections.get(version);
  assert.ok(release, `Missing CHANGELOG entry for ${version}.`);
  let category;
  let count = 0;
  const categories = new Set();
  for (const line of release.lines) {
    if (!line.trim()) continue;
    const heading = /^### (Added|Improved|Changed|Fixed|Removed|Security|Known Issues)$/.exec(line);
    if (heading) {
      assert.ok(category === undefined || count > 0, 'Empty changelog category.');
      category = heading[1];
      assert.ok(!categories.has(category), `Duplicate changelog category: ${category}`);
      categories.add(category);
      count = 0;
    } else {
      assert.ok(category && /^- \S/.test(line), 'Release notes must use English categories and nonempty bullet points.');
      assert.ok(!/\b(TODO|TBD|PLACEHOLDER)\b/i.test(line), 'Release notes contain a placeholder.');
      count += 1;
    }
  }
  assert.ok(count > 0, `CHANGELOG entry for ${version} has no changes or an empty category.`);
  return `${release.heading}\n\n${release.lines.join('\n').trim()}\n`;
}

export async function releaseNotes({ rootDirectory = '.', tag } = {}) {
  const manifest = await readReleaseManifest({ rootDirectory });
  return extractReleaseNotes(await readFile(resolve(rootDirectory, 'CHANGELOG.md'), 'utf8'), manifest.version, tag);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const { values } = parseArgs({ options: {
      check: { type: 'boolean', default: false },
      root: { type: 'string', default: '.' },
      tag: { type: 'string' },
      output: { type: 'string' },
    } });
    assert.ok(!(values.check && values.output), 'Use --check or --output, not both.');
    const notes = await releaseNotes({ rootDirectory: values.root, tag: values.tag });
    if (values.output) await writeFile(values.output, notes);
    else if (!values.check) process.stdout.write(notes);
  } catch (error) {
    console.error(`::error::Release notes validation failed: ${error.message}`);
    process.exitCode = 1;
  }
}

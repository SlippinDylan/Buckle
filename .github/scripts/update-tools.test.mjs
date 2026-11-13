import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

function createArchive(directory, archives, publicKey, version, build, executable = '/usr/bin/true') {
  const app = join(directory, `Buckle-${version}.app`);
  mkdirSync(join(app, 'Contents/MacOS'), { recursive: true });
  copyFileSync(executable, join(app, 'Contents/MacOS/Buckle'));
  writeFileSync(join(app, 'Contents/Info.plist'), `<?xml version="1.0"?><plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>studio.slippindylan.Buckle.UpdateTest</string>
    <key>CFBundleName</key><string>Buckle</string>
    <key>CFBundleExecutable</key><string>Buckle</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${version}</string>
    <key>CFBundleVersion</key><string>${build}</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>SUPublicEDKey</key><string>${publicKey}</string>
    <key>SURequireSignedFeed</key><true/>
    </dict></plist>`);
  execFileSync('codesign', ['--force', '--sign', '-', app], { stdio: 'pipe' });
  execFileSync('ditto', ['-c', '-k', '--keepParent', app, join(archives, `Buckle-${version}.zip`)]);
}

test('official Sparkle tools produce and verify a signed feed and reject invalid inputs', {
  skip: process.platform !== 'darwin' || !existsSync('build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast'),
}, () => {
  const directory = mkdtempSync(join(tmpdir(), 'buckle-update-test-'));
  try {
    const pair = generateKeyPairSync('ed25519');
    const privateKey = pair.privateKey.export({ format: 'der', type: 'pkcs8' }).subarray(-32).toString('base64');
    const publicKey = pair.publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
    const env = { ...process.env, SPARKLE_ED_PRIVATE_KEY: privateKey, SPARKLE_PUBLIC_KEY: publicKey };
    const archives = join(directory, 'archives');
    mkdirSync(archives);
    const invoke = (url, overrides = {}) => spawnSync('bash', ['Scripts/prepare-update.sh', archives, url], {
      encoding: 'utf8', env: { ...env, ...overrides },
    });
    for (const url of ['http://example.test/', 'https://example.test:0/', 'https://user@example.test/', 'https://example.test/?token=x']) {
      const result = invoke(url);
      assert.notEqual(result.status, 0);
      assert.ok(!result.stdout.includes(privateKey));
      assert.ok(!result.stderr.includes(privateKey));
      assert.ok(!existsSync(join(archives, 'appcast.xml')));
    }
    assert.notEqual(invoke('https://example.test/', { SPARKLE_PUBLIC_KEY: Buffer.alloc(32).toString('base64') }).status, 0);
    createArchive(directory, archives, publicKey, '0.1.0', 1);
    writeFileSync(join(archives, 'Buckle-0.1.0.md'), 'Release notes from the archive directory.');
    const result = invoke('https://example.test/updates');
    assert.equal(result.status, 0, result.stderr);
    assert.ok(existsSync(join(archives, 'appcast.xml')), result.stdout + result.stderr);
    const feed = readFileSync(join(archives, 'appcast.xml'), 'utf8');
    assert.ok(feed.includes('https://example.test/updates/Buckle-0.1.0.zip'));
    assert.ok(feed.includes('sparkle:edSignature='));
    assert.ok(feed.includes('<sparkle:version>1</sparkle:version>'));
    assert.ok(feed.includes('<sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>'));
    assert.ok(feed.includes('Release notes from the archive directory.'));
    assert.ok(!feed.includes(privateKey));
    assert.equal(invoke('https://example.test/updates').status, 0);
    const sign = 'build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update';
    writeFileSync(join(archives, 'appcast.xml'), feed.replace('Buckle-0.1.0.zip', 'tampered.zip'));
    const tampered = spawnSync(sign, ['--verify', '--ed-key-file', '-', join(archives, 'appcast.xml')], {
      input: privateKey, encoding: 'utf8',
    });
    assert.notEqual(tampered.status, 0);
    assert.notEqual(invoke('https://example.test/updates').status, 0);
    assert.ok(readFileSync(join(archives, 'appcast.xml'), 'utf8').includes('tampered.zip'));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('update generation rejects reused builds before replacing the published feed', {
  skip: process.platform !== 'darwin' || !existsSync('build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast'),
}, () => {
  const directory = mkdtempSync(join(tmpdir(), 'buckle-version-test-'));
  try {
    const pair = generateKeyPairSync('ed25519');
    const privateKey = pair.privateKey.export({ format: 'der', type: 'pkcs8' }).subarray(-32).toString('base64');
    const publicKey = pair.publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
    const env = { ...process.env, SPARKLE_ED_PRIVATE_KEY: privateKey, SPARKLE_PUBLIC_KEY: publicKey };
    const initial = join(directory, 'initial');
    mkdirSync(initial);
    createArchive(directory, initial, publicKey, '0.1.0', 1);
    const invoke = (archives, version) => spawnSync('bash', ['Scripts/prepare-update.sh', archives, `https://example.test/v${version}/`], {
      encoding: 'utf8', env,
    });
    const first = invoke(initial, '0.1.0');
    assert.equal(first.status, 0, first.stderr);
    const previous = readFileSync(join(initial, 'appcast.xml'));
    const changed = join(directory, 'changed-archive');
    mkdirSync(changed);
    copyFileSync(join(initial, 'appcast.xml'), join(changed, 'appcast.xml'));
    createArchive(directory, changed, publicKey, '0.1.0', 1, '/usr/bin/false');
    const replacement = invoke(changed, '0.1.0');
    assert.notEqual(replacement.status, 0);
    assert.match(replacement.stderr, /published build cannot be reused/);
    assert.deepEqual(readFileSync(join(changed, 'appcast.xml')), previous);
    for (const [version, build, accepted] of [['0.1.1', 1, false], ['0.1.0', 2, false], ['0.0.9', 2, false], ['0.1.1', 2, true]]) {
      const archives = join(directory, `candidate-${version}-${build}`);
      mkdirSync(archives);
      copyFileSync(join(initial, 'appcast.xml'), join(archives, 'appcast.xml'));
      createArchive(directory, archives, publicKey, version, build);
      const result = invoke(archives, version);
      if (accepted) {
        assert.equal(result.status, 0, result.stderr);
      } else {
        assert.notEqual(result.status, 0, 'A reused build or non-increasing version must be rejected.');
        assert.deepEqual(readFileSync(join(archives, 'appcast.xml')), previous);
      }
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

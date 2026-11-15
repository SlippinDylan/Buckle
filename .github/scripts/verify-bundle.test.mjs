import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import test from 'node:test';

// Stub platform inspection, not validation: malformed bundles exercise the real script.
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'buckle-bundle-check-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const bin = join(root, 'bin');
  await mkdir(bin);
  const stub = `#!/usr/bin/env python3
import os, plistlib, sys
from pathlib import Path
name = Path(sys.argv[0]).name
if name == 'tiffutil':
    print('Image Width: 20 Image Length: 20\\nImage Width: 40 Image Length: 40')
elif name == 'lipo':
    print(os.environ['TEST_EXTENSION_ARCHS'] if 'BuckleFinder.appex' in sys.argv[-1] else os.environ['TEST_ARCHS'])
elif '--entitlements' in sys.argv:
    sys.stdout.buffer.write(plistlib.dumps({'com.apple.security.app-sandbox': True,
        'com.apple.security.temporary-exception.files.home-relative-path.read-only': ['/Library/Application Support/Buckle/Finder/']}))
elif '-d' in sys.argv:
    print('Signature=adhoc', file=sys.stderr)
`;
  for (const name of ['codesign', 'lipo', 'tiffutil']) {
    await writeFile(join(bin, name), stub, { mode: 0o755 });
  }
  const app = join(root, 'Buckle.app');
  execFileSync('python3', ['-c', `
import plistlib, sys
from pathlib import Path
app = Path(sys.argv[1])
extension = app / 'Contents/PlugIns/BuckleFinder.appex'
for bundle, executable in ((app, 'Buckle'), (extension, 'BuckleFinder')):
    binary = bundle / 'Contents/MacOS' / executable
    binary.parent.mkdir(parents=True)
    binary.touch()
    binary.chmod(0o755)
host = {'CFBundleIdentifier': 'studio.slippindylan.Buckle', 'CFBundleShortVersionString': '0.1.0',
    'CFBundleVersion': '1', 'CFBundleIconName': 'Buckle', 'CFBundleIconFile': 'Buckle',
    'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True, 'AppUpdaterEnabled': 'NO'}
ext = {'CFBundleIdentifier': 'studio.slippindylan.Buckle.Finder', 'CFBundleShortVersionString': '0.1.0',
    'CFBundleVersion': '1', 'CFBundlePackageType': 'XPC!',
    'NSExtension': {'NSExtensionPrincipalClass': 'BuckleFinder.BuckleFinderSync'}}
for bundle, info in ((app, host), (extension, ext)):
    (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
resources = app / 'Contents/Resources'
resources.mkdir()
for name in ('Buckle.icns', 'Assets.car', 'MenuBarIconTemplate.tiff', 'ThirdPartyNotices.txt'):
    (resources / name).touch()
for language in ('en', 'zh-Hans', 'zh-Hant', 'ja', 'ko', 'de', 'fr', 'es'):
    strings = resources / 'PermissionFlow_PermissionFlow.bundle/Contents/Resources' / (language + '.lproj') / 'Localizable.strings'
    strings.parent.mkdir(parents=True)
    strings.touch()
framework = app / 'Contents/Frameworks/Sparkle.framework/Versions/B'
(framework / 'Resources').mkdir(parents=True)
(framework / 'Resources/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': '2.10.0'}))
for component in ('Sparkle', 'Autoupdate', 'Updater.app', 'XPCServices/Installer.xpc', 'XPCServices/Downloader.xpc'):
    target = framework / component
    target.parent.mkdir(parents=True, exist_ok=True)
    target.touch()
`, app]);
  return {
    app,
    run: ({ distribution = false, legacy = false, archs = 'arm64 x86_64', extensionArchs = archs } = {}) => spawnSync('bash',
      ['Scripts/verify-bundle.sh', ...(distribution ? ['--distribution'] : []), ...(legacy ? ['--legacy-updater-key'] : []), app],
      { encoding: 'utf8', env: { ...process.env, PATH: bin + delimiter + process.env.PATH,
        TEST_ARCHS: archs, TEST_EXTENSION_ARCHS: extensionArchs } }),
  };
}

test('bundle checks allow single-architecture development and require Universal 2 for distribution', async (t) => {
  const { run } = await fixture(t);
  assert.equal(run().status, 0);
  assert.equal(run({ archs: 'arm64' }).status, 0);
  assert.equal(run({ distribution: true }).status, 0);
  for (const archs of ['arm64', 'x86_64']) {
    const result = run({ distribution: true, archs });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Universal 2/);
  }
  assert.notEqual(run({ extensionArchs: 'arm64' }).status, 0);
});

test('matching host and extension identifiers cannot impersonate Buckle', async (t) => {
  const { app, run } = await fixture(t);
  execFileSync('python3', ['-c', `
import plistlib, sys
from pathlib import Path
app = Path(sys.argv[1])
for bundle, identity in ((app, 'other.Buckle'), (app / 'Contents/PlugIns/BuckleFinder.appex', 'other.Buckle.Finder')):
    path = bundle / 'Contents/Info.plist'
    info = plistlib.loads(path.read_bytes())
    info['CFBundleIdentifier'] = identity
    path.write_bytes(plistlib.dumps(info))
`, app]);
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /bundle identifier/);
});

test('Finder extension identity is checked independently of the host', async (t) => {
  const { app, run } = await fixture(t);
  execFileSync('python3', ['-c', `
import plistlib, sys
from pathlib import Path
path = Path(sys.argv[1]) / 'Contents/PlugIns/BuckleFinder.appex/Contents/Info.plist'
info = plistlib.loads(path.read_bytes())
info['CFBundleIdentifier'] = 'other.Finder'
path.write_bytes(plistlib.dumps(info))
`, app]);
  const result = run({ distribution: true });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Finder bundle identifier/);
});

 test('historical updater key requires explicit legacy validation', async (t) => {
  const { app, run } = await fixture(t);
  execFileSync('python3', ['-c', `
import plistlib, sys
from pathlib import Path
path = Path(sys.argv[1]) / 'Contents/Info.plist'
info = plistlib.loads(path.read_bytes())
info['BuckleUpdaterEnabled'] = info.pop('AppUpdaterEnabled')
path.write_bytes(plistlib.dumps(info))
`, app]);
  assert.notEqual(run().status, 0);
  assert.equal(run({ legacy: true }).status, 0);
});

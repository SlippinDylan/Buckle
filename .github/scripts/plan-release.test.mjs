import { test } from 'node:test';
import assert from 'node:assert/strict';
import { needsRelease } from './plan-release.mjs';

test('only an absent release allows automatic publishing', async () => {
  assert.equal(await needsRelease('SlippinDylan/Buckle', '0.1.0', 'fake', async (url, options) => {
    assert.equal(url, 'https://api.github.com/repos/SlippinDylan/Buckle/releases/tags/v0.1.0');
    assert.equal(options.headers.Authorization, 'Bearer fake');
    return { status: 404 };
  }), true);
  assert.equal(await needsRelease('SlippinDylan/Buckle', '0.1.0', 'fake', async () => ({
    status: 200, ok: true, json: async () => ({ draft: false, prerelease: false }),
  })), false);
});

test('API failures and incomplete releases cannot masquerade as an absent release', async () => {
  for (const status of [401, 403, 429, 500]) {
    await assert.rejects(needsRelease('SlippinDylan/Buckle', '0.1.0', 'fake', async () => ({ status, ok: false })),
      { message: `Cannot check release: HTTP ${status}.` });
  }
  for (const release of [{ draft: true, prerelease: false }, { draft: false, prerelease: true }]) {
    await assert.rejects(needsRelease('SlippinDylan/Buckle', '0.1.0', 'fake', async () => ({
      status: 200, ok: true, json: async () => release,
    })), /already exists as a draft or prerelease/);
  }
});

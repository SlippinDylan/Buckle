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

test('release tags must resolve to the exact build commit, including annotated tags', async () => {
  const { verifyReleaseTag } = await import('./plan-release.mjs');
  const commit = 'a'.repeat(40);
  const annotation = 'b'.repeat(40);
  const repository = 'SlippinDylan/Buckle';
  const invoke = (responses) => verifyReleaseTag(repository, '0.1.2', commit, 'fake', async (url, options) => {
    assert.equal(options.headers.Authorization, 'Bearer fake');
    const response = responses.shift();
    assert.ok(response, `Unexpected request: ${url}`);
    assert.equal(url, `https://api.github.com/repos/${repository}/${response.path}`);
    return { status: response.status ?? 200, ok: (response.status ?? 200) === 200, json: async () => ({ object: response.object }) };
  });
  const ref = 'git/ref/tags/v0.1.2';
  await invoke([{ path: ref, status: 404 }]);
  await invoke([{ path: ref, object: { type: 'commit', sha: commit } }]);
  await invoke([
    { path: ref, object: { type: 'tag', sha: annotation } },
    { path: `git/tags/${annotation}`, object: { type: 'commit', sha: commit } },
  ]);
  await invoke([
    { path: ref, object: { type: 'tag', sha: annotation } },
    { path: `git/tags/${annotation}`, object: { type: 'tag', sha: 'c'.repeat(40) } },
    { path: `git/tags/${'c'.repeat(40)}`, object: { type: 'commit', sha: commit } },
  ]);
  await assert.rejects(invoke([{ path: ref, object: { type: 'commit', sha: 'c'.repeat(40) } }]), /does not point to the build commit/);
  await assert.rejects(invoke([
    { path: ref, object: { type: 'tag', sha: annotation } },
    { path: `git/tags/${annotation}`, object: { type: 'commit', sha: 'c'.repeat(40) } },
  ]), /does not point to the build commit/);
  for (const status of [401, 403, 429, 500]) {
    await assert.rejects(invoke([{ path: ref, status }]), new RegExp(`HTTP ${status}`));
  }
  await assert.rejects(invoke([
    { path: ref, object: { type: 'tag', sha: annotation } },
    { path: `git/tags/${annotation}`, status: 404 },
  ]), /HTTP 404/);
  await assert.rejects(invoke([{ path: ref, object: { type: 'tree', sha: annotation } }]), /must resolve to a commit/);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { notification, send } from './discord-notify.mjs';

const repository = { full_name: 'SlippinDylan/Buckle' };

test('untrusted event text cannot ping Discord members', () => {
  const payload = notification('push', { repository, ref: 'refs/heads/main', head_commit: { message: '@everyone <@123> **hello**' } });
  assert.deepEqual(payload.allowed_mentions, { parse: [] });
  assert.ok(payload.embeds[0].description.includes('\\@everyone'));
  assert.equal(payload.embeds[0].url, 'https://github.com/SlippinDylan/Buckle');
});

test('reports workflow failures accurately', () => {
  const event = { repository, action: 'completed', workflow_run: { name: 'CI', conclusion: 'failure', head_branch: 'main', id: 42 } };
  assert.equal(notification('workflow_run', event).embeds[0].color, 0xed4245);
});

test('ignores unrelated workflows and unknown events', () => {
  assert.equal(notification('workflow_run', { repository, workflow_run: { name: 'Other' } }), null);
  assert.equal(notification('unknown', { repository }), null);
});

test('request failures do not reveal webhook credentials', async () => {
  const webhook = 'https://discord.com/api/webhooks/fake/test-secret';
  await assert.rejects(send({}, webhook, async () => { throw new Error(webhook); }), { message: 'Discord request failed.' });
  await assert.rejects(send({}, 'https://example.com/api/webhooks/fake'), { message: 'Invalid Discord webhook configuration.' });
  await assert.rejects(send({}, webhook, async () => ({ ok: false, status: 429 })), { message: 'Discord returned HTTP 429.' });
});

test('sends JSON with wait enabled', async () => {
  let invoked = false;
  await send({ allowed_mentions: { parse: [] } }, 'https://discord.com/api/webhooks/fake/test', async (url, options) => {
    invoked = true;
    assert.equal(url.searchParams.get('wait'), 'true');
    assert.equal(options.method, 'POST');
    assert.deepEqual(JSON.parse(options.body), { allowed_mentions: { parse: [] } });
    return { ok: true };
  });
  assert.ok(invoked);
});

test('update feed failures and successes have distinct release notifications', () => {
  for (const [conclusion, color] of [['failure', 0xed4245], ['success', 0x57f287]]) {
    const event = { repository, action: 'completed', workflow_run: {
      name: 'Publish Update Feed', id: 42, conclusion, head_branch: 'main', head_sha: 'abcdef123456',
      run_number: 7, html_url: 'https://github.com/SlippinDylan/Buckle/actions/runs/42',
    } };
    const embed = notification('workflow_run', event).embeds[0];
    assert.equal(embed.color, color);
    assert.ok(embed.title.includes('更新源同步'));
    assert.ok(embed.title.includes(conclusion));
    assert.equal(embed.url, event.workflow_run.html_url);
  }
  const release = notification('release', { repository, release: { tag_name: 'v0.1.0' } });
  assert.ok(release.embeds[0].title.includes('GitHub Release'));
});

test('workflow trigger includes every workflow handled by the notification script', async () => {
  const { readFile } = await import('node:fs/promises');
  const source = await readFile(new URL('../workflows/discord-notify.yml', import.meta.url), 'utf8');
  const names = source.match(/workflows: \[([^\]]+)\]/)[1].split(',').map(name => name.trim());
  assert.deepEqual(names, ['CI', 'Publish Update Feed']);
});

test('Dependabot push notifications are excluded while PR and CI notifications remain enabled', async () => {
  const { readFile } = await import('node:fs/promises');
  const source = await readFile(new URL('../workflows/discord-notify.yml', import.meta.url), 'utf8');
  const push = source.match(/^  push:\n((?:    .+\n)+)/m)?.[1];
  assert.ok(push, 'Push notification trigger must remain enabled.');
  assert.match(push, /branches-ignore: \['dependabot\/\*\*'\]/);
  assert.doesNotMatch(push, /^    branches:/m);
  assert.match(source, /^  pull_request_target:/m);
  assert.match(source, /^  workflow_run:/m);
  assert.match(source, /^  release:/m);
});

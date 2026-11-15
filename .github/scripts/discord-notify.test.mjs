import { test } from 'node:test';
import assert from 'node:assert/strict';
import { notification, stageStartNotification, stageResultNotification, publicationSuccessNotification, ciStartNotifications, enrichWorkflowResult, send } from './discord-notify.mjs';

const repository = { full_name: 'SlippinDylan/Buckle' };

test('untrusted event text cannot ping Discord members', () => {
  const payload = notification('push', { repository, ref: 'refs/heads/main', head_commit: { message: '@everyone <@123> **hello**' } });
  assert.deepEqual(payload.allowed_mentions, { parse: [] });
  assert.ok(payload.embeds[0].description.includes('\\@everyone'));
  assert.equal(payload.embeds[0].url, 'https://github.com/SlippinDylan/Buckle');
});

test('reports workflow failures accurately', () => {
  const event = { repository, action: 'completed', workflow_run: { name: 'CI', event: 'push', conclusion: 'failure', head_branch: 'main', id: 42 } };
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
      name: 'Publish Update Feed', event: 'workflow_dispatch', id: 42, conclusion, stageConclusion: conclusion, head_branch: 'main', head_sha: 'abcdef123456',
      run_number: 7, html_url: 'https://github.com/SlippinDylan/Buckle/actions/runs/42',
    } };
    const embed = notification('workflow_run', event).embeds[0];
    assert.equal(embed.color, color);
    assert.ok(embed.title.includes('Sparkle 与 Homebrew 同步'));
    assert.ok(embed.title.includes(conclusion === 'success' ? '成功' : '失败'));
    assert.equal(embed.url, event.workflow_run.html_url);
  }
  const release = notification('release', { repository, release: { tag_name: 'v0.1.0' } });
  assert.equal(release, null);
});

test('workflow trigger includes every workflow handled by the notification script', async () => {
  const { readFile } = await import('node:fs/promises');
  const source = await readFile(new URL('../workflows/discord-notify.yml', import.meta.url), 'utf8');
  const names = source.match(/workflows: \[([^\]]+)\]/)[1].split(',').map(name => name.trim());
  assert.deepEqual(names, ['CI', 'Package', 'Release', 'Publish Update Feed']);
});

test('Dependabot push notifications are excluded while PR and CI notifications remain enabled', async () => {
  const { readFile } = await import('node:fs/promises');
  const source = await readFile(new URL('../workflows/discord-notify.yml', import.meta.url), 'utf8');
  const push = source.match(/^  push:\n((?:    .+\n)+)/m)?.[1];
  assert.ok(push, 'Push notification trigger must remain enabled.');
  assert.match(push, /branches-ignore: \['main', 'dependabot\/\*\*'\]/);
  assert.doesNotMatch(push, /^    branches:/m);
  assert.match(source, /^  pull_request_target:/m);
  assert.match(source, /^  workflow_run:/m);
  assert.doesNotMatch(source, /^  release:/m);
});


function runEvent(name, conclusion = 'success') {
  return { repository, action: 'completed', workflow_run: {
    name, event: 'push', conclusion, head_branch: 'main', head_sha: 'abcdef123456', id: 42, run_attempt: 3, run_number: 7,
  } };
}

function jobsResponse(jobs, total = jobs.length) {
  return { ok: true, json: async () => ({ total_count: total, jobs }) };
}

test('PR conversation comments and reviews link to the PR rather than an Issue', () => {
  const event = { repository, issue: { number: 9, title: 'Review me', pull_request: {} } };
  assert.equal(notification('issue_comment', event).embeds[0].url, 'https://github.com/SlippinDylan/Buckle/pull/9');
  delete event.issue.pull_request;
  assert.equal(notification('issue_comment', event).embeds[0].url, 'https://github.com/SlippinDylan/Buckle/issues/9');
  for (const kind of ['pull_request_review', 'pull_request_review_comment']) {
    const payload = notification(kind, { repository, review: { state: 'approved' }, pull_request: { number: 9, title: 'Review me' } });
    assert.equal(payload.embeds[0].url, 'https://github.com/SlippinDylan/Buckle/pull/9');
  }
});

test('fork reviews skip secrets while trusted default-branch automation handles reviews', async () => {
  const { readFile } = await import('node:fs/promises');
  const source = await readFile(new URL('../workflows/discord-notify.yml', import.meta.url), 'utf8');
  assert.match(source, /^  pull_request_review:/m);
  assert.match(source, /^  pull_request_review_comment:/m);
  assert.match(source, /!startsWith\(github.event_name, 'pull_request_review'\)/);
  assert.match(source, /github.event.pull_request.head.repo.full_name == github.repository/);
  assert.match(source, /ref: \$\{\{ github.event.repository.default_branch \}\}/);
  assert.match(source, /actions: read/);
  assert.match(source, /GITHUB_TOKEN: \$\{\{ github.token \}\}/);
});

test('packaging success depends on the current attempt actual Build DMG job', async () => {
  for (const [conclusion, expected] of [['success', '成功'], ['skipped', '已跳过']]) {
    const event = runEvent('Package');
    await enrichWorkflowResult(event, 'test-token', async (url, options) => {
      assert.equal(url, 'https://api.github.com/repos/SlippinDylan/Buckle/actions/runs/42/attempts/3/jobs?per_page=100');
      assert.equal(options.headers.Authorization, 'Bearer test-token');
      assert.equal(options.redirect, 'error');
      return jobsResponse([{ name: 'Validate package request', conclusion: 'success' }, { name: 'Build DMG', conclusion }]);
    });
    const embed = notification('workflow_run', event).embeds[0];
    assert.ok(embed.title.includes(expected));
    assert.equal(embed.description.includes('未确认生成安装包'), conclusion !== 'success');
    assert.equal(embed.color, conclusion === 'success' ? 0x57f287 : 0x99aab5);
  }
});

test('CI can succeed after deliberately skipping App compilation', async () => {
  const event = runEvent('CI');
  await enrichWorkflowResult(event, 'test-token', async () => jobsResponse([{ name: 'Build Debug app', conclusion: 'skipped' }]));
  assert.equal(notification('workflow_run', event), null);
});

test('automatic Release workflow reports publication independently of distribution', async () => {
  for (const [name, job] of [['Release', 'Publish GitHub Release'], ['Publish Update Feed', 'Synchronize distribution metadata']]) {
    const event = runEvent(name);
    await enrichWorkflowResult(event, 'test-token', async () => jobsResponse([{ name: job, conclusion: 'success' }]));
    const payload = notification('workflow_run', event);
    if (name === 'Release') assert.equal(payload, null);
    else assert.ok(payload.embeds[0].title.includes('Sparkle 与 Homebrew 同步成功'));
  }
});

test('starts report workflow execution without claiming a generated artifact', async () => {
  const event = { ...runEvent('Package'), action: 'in_progress' };
  await enrichWorkflowResult(event, undefined, async () => assert.fail('Start events must not fetch a completed stage'));
  assert.equal(notification('workflow_run', event), null);
});

test('missing or contradictory job data cannot produce a success message', async () => {
  for (const jobs of [[], [{ name: 'Build DMG', conclusion: 'failure' }], [
    { name: 'Build DMG', conclusion: 'success' }, { name: 'Build DMG', conclusion: 'success' },
  ], [{ name: 'Build DMG', conclusion: null }]]) {
    await assert.rejects(enrichWorkflowResult(runEvent('Package'), 'token', async () => jobsResponse(jobs)));
  }
  await assert.rejects(enrichWorkflowResult(runEvent('Package'), 'token', async () => jobsResponse([], 101)));
  await assert.rejects(enrichWorkflowResult(runEvent('Package'), undefined), /Missing Actions token/);
  assert.throws(() => notification('workflow_run', runEvent('Package')), /Missing or unknown/);
});

test('early failures, timeout and cancellation remain distinct even without the build stage', async () => {
  for (const [result, label] of [['failure', '失败'], ['timed_out', '超时'], ['cancelled', '已取消']]) {
    const event = runEvent('Package', result);
    await enrichWorkflowResult(event, 'token', async () => jobsResponse([]));
    const embed = notification('workflow_run', event).embeds[0];
    assert.ok(embed.title.includes(label));
    assert.ok(embed.description.includes('未确认生成安装包'));
  }
});

test('Actions fetch errors do not disclose credentials or fabricate successful results', async () => {
  await assert.rejects(enrichWorkflowResult(runEvent('Package'), 'private-token', async () => { throw new Error('private-token'); }),
    { message: 'Cannot read workflow jobs from GitHub.' });
  await assert.rejects(enrichWorkflowResult(runEvent('Package'), 'private-token', async () => ({ ok: false, status: 403 })),
    { message: 'Cannot read workflow jobs: HTTP 403.' });
});


test('failed distribution requests report only their own failure after publication', async () => {
  for (const result of ['failure', 'timed_out', 'cancelled']) {
    const event = runEvent('Release', result);
    await enrichWorkflowResult(event, 'token', async () => jobsResponse([
      { name: 'Publish GitHub Release', conclusion: 'success' },
      { name: 'Request distribution synchronization', conclusion: result },
    ]));
    const embed = notification('workflow_run', event).embeds[0];
    assert.ok(embed.title.includes('分发触发'));
    assert.ok(!embed.title.includes('发行成功'));
    assert.ok(embed.description.includes('GitHub Release 已发布'));
    assert.ok(embed.description.includes('分发触发'));
    assert.ok(embed.description.includes('整体流程'));
  }
});

test('failed packaging job including artifact upload cannot claim a generated installer', async () => {
  const event = runEvent('Package', 'failure');
  await enrichWorkflowResult(event, 'token', async () => jobsResponse([{ name: 'Build DMG', conclusion: 'failure' }]));
  const embed = notification('workflow_run', event).embeds[0];
  assert.ok(embed.title.includes('失败'));
  assert.ok(embed.description.includes('未确认生成安装包'));
  assert.ok(!embed.title.includes('成功'));
});


test('explicit trusted stage starts produce one stage-specific payload without webhook metadata', () => {
  const environment = {
    GITHUB_REPOSITORY: 'SlippinDylan/Buckle', GITHUB_SHA: 'a'.repeat(40), GITHUB_RUN_ID: '42',
    GITHUB_REF_NAME: 'main',
  };
  for (const name of ['CI', 'Package', 'Release', 'Publish Update Feed']) {
    const payload = stageStartNotification(name, environment);
    assert.equal(payload.embeds.length, 1);
    assert.ok(payload.embeds[0].title.includes('已开始'));
    assert.ok(!payload.embeds[0].title.includes('流程已开始'));
    assert.equal(payload.embeds[0].url, 'https://github.com/SlippinDylan/Buckle/actions/runs/42');
    assert.deepEqual(payload.allowed_mentions, { parse: [] });
  }
  assert.throws(() => stageStartNotification('Discord Activity Notifications', environment), /Unknown workflow stage/);
  assert.throws(() => stageStartNotification('Package; shell', environment), /Unknown workflow stage/);
  for (const override of [{ GITHUB_REPOSITORY: 'other/repo/path' }, { GITHUB_SHA: 'bad' },
    { GITHUB_RUN_ID: '-1' }, { GITHUB_RUN_ID: 'not-a-number' }, { GITHUB_RUN_ID: '9007199254740992' }]) {
    assert.throws(() => stageStartNotification('Package', { ...environment, ...override }));
  }
});

test('stage-start CLI validates arguments before reading an event file or sending', async () => {
  const { spawnSync } = await import('node:child_process');
  const invoke = (...arguments_) => spawnSync(process.execPath, ['.github/scripts/discord-notify.mjs', ...arguments_], {
    encoding: 'utf8', env: { ...process.env, GITHUB_EVENT_PATH: '/nonexistent/event.json' },
  });
  for (const arguments_ of [['--unknown'], ['--stage-start'], ['--stage-start', 'Other'], ['--stage-start', 'Package', 'extra']]) {
    const result = invoke(...arguments_);
    assert.notEqual(result.status, 0);
    assert.ok(!result.stderr.includes('ENOENT'));
    assert.ok(!result.stderr.includes('Invalid Discord webhook configuration'));
  }
});

test('main CI owns the ordered push and check start, reruns only announce checks', () => {
  const environment = {
    GITHUB_REPOSITORY: 'SlippinDylan/Buckle', GITHUB_SHA: 'a'.repeat(40), GITHUB_RUN_ID: '42',
    GITHUB_REF_NAME: 'main', GITHUB_EVENT_NAME: 'push', GITHUB_RUN_ATTEMPT: '1',
  };
  const event = { repository, ref: 'refs/heads/main', head_commit: { message: 'Release changes' } };
  const payloads = ciStartNotifications(event, environment);
  assert.deepEqual(payloads.map(payload => payload.embeds[0].title), ['Buckle · 代码已推送', 'Buckle · 检查已开始']);
  for (const overrides of [{ GITHUB_RUN_ATTEMPT: '2' }, { GITHUB_EVENT_NAME: 'workflow_dispatch' }]) {
    assert.deepEqual(ciStartNotifications({}, { ...environment, ...overrides }).map(payload => payload.embeds[0].title),
      ['Buckle · 检查已开始']);
  }
});

test('PR and Dependabot CI results do not enter the main release notification chain', async () => {
  for (const overrides of [{ event: 'pull_request' }, { event: 'workflow_run' }, { event: 'release' }, { head_branch: 'dependabot/npm/update' }, { head_branch: 'feature' }]) {
    const event = runEvent('CI');
    Object.assign(event.workflow_run, overrides);
    await enrichWorkflowResult(event, undefined, async () => assert.fail('Ignored workflow must not fetch jobs'));
    assert.equal(notification('workflow_run', event), null);
  }
});

test('Release reports the actual failed phase and stays silent when no release was eligible', async () => {
  for (const [jobs, expected] of [
    [[{ name: 'Validate release request', conclusion: 'failure' }], '发行前检查失败'],
    [[{ name: 'Build release installer', conclusion: 'failure' }, { name: 'Publish GitHub Release', conclusion: 'skipped' }], '打包失败'],
    [[{ name: 'Build release installer', conclusion: 'success' }, { name: 'Publish GitHub Release', conclusion: 'failure' }], '发行失败'],
  ]) {
    const event = runEvent('Release', 'failure');
    await enrichWorkflowResult(event, 'token', async () => jobsResponse(jobs));
    assert.equal(notification('workflow_run', event).embeds[0].title, `Buckle · ${expected}`);
  }
  const event = runEvent('Release');
  await enrichWorkflowResult(event, 'token', async () => jobsResponse([
    { name: 'Validate release request', conclusion: 'success' },
    { name: 'Build release installer', conclusion: 'skipped' },
    { name: 'Publish GitHub Release', conclusion: 'skipped' },
  ]));
  assert.equal(notification('workflow_run', event), null);
});

test('explicit packaging results do not read event metadata and validate result values', () => {
  const environment = {
    GITHUB_REPOSITORY: 'SlippinDylan/Buckle', GITHUB_SHA: 'a'.repeat(40), GITHUB_RUN_ID: '42', GITHUB_REF_NAME: 'main',
  };
  assert.equal(stageResultNotification('Release', 'success', environment).embeds[0].title, 'Buckle · 打包成功');
  assert.equal(stageResultNotification('Release', 'failure', environment).embeds[0].title, 'Buckle · 打包失败');
  assert.throws(() => stageResultNotification('Release', 'skipped', environment), /Unknown stage result/);
  assert.throws(() => stageResultNotification('Other', 'success', environment), /Unknown workflow stage/);
});

test('completed lifecycle events are the sole result notification owner', async () => {
  const { readFile } = await import('node:fs/promises');
  const source = await readFile(new URL('../workflows/discord-notify.yml', import.meta.url), 'utf8');
  assert.match(source, /types: \[completed\]/);
  assert.doesNotMatch(source, /in_progress/);
  assert.doesNotMatch(source, /^  release:/m);
  assert.match(source, /workflow_run.head_branch == 'main'/);
});

test('successful CI and publication lifecycle events do not repeat direct stage results', async () => {
  assert.equal(notification('workflow_run', runEvent('CI')), null);
  for (const conclusion of ['success', 'skipped']) {
    const event = runEvent('Release');
    await enrichWorkflowResult(event, 'token', async () => jobsResponse([
      { name: 'Publish GitHub Release', conclusion: 'success' },
      { name: 'Request distribution synchronization', conclusion },
    ]));
    assert.equal(notification('workflow_run', event), null);
  }
});

test('release-triggered synchronization reports tag-based workflow results', async () => {
  for (const result of ['success', 'failure']) {
    const event = runEvent('Publish Update Feed', result);
    Object.assign(event.workflow_run, { event: 'release', head_branch: 'v0.2.1' });
    await enrichWorkflowResult(event, 'token', async () => jobsResponse([
      { name: 'Synchronize distribution metadata', conclusion: result },
    ]));
    assert.ok(notification('workflow_run', event).embeds[0].title.includes(result === 'success' ? '成功' : '失败'));
  }
});

test('publication success is distinct from packaging and uses the actual release SHA', () => {
  const environment = {
    GITHUB_REPOSITORY: 'SlippinDylan/Buckle', GITHUB_SHA: 'a'.repeat(40), RELEASE_SHA: 'b'.repeat(40),
    GITHUB_RUN_ID: '42', GITHUB_REF_NAME: 'main',
  };
  const published = publicationSuccessNotification(environment).embeds[0];
  assert.equal(published.title, 'Buckle · 发行成功');
  assert.ok(published.description.includes('bbbbbbb'));
  assert.ok(!published.description.includes('aaaaaaa'));
  assert.equal(stageResultNotification('Release', 'success', environment).embeds[0].title, 'Buckle · 打包成功');
  assert.equal(stageResultNotification('CI', 'success', environment).embeds[0].title, 'Buckle · 检查成功');
  assert.throws(() => publicationSuccessNotification({ ...environment, RELEASE_SHA: 'invalid' }), /Invalid build commit SHA/);
});

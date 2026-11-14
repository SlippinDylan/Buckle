import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const clean = value => String(value ?? '').replace(/\s+/g, ' ').slice(0, 240);
const escape = value => clean(value).replace(/([\\`*_~|<>@\[\]])/g, '\\$1');

export function notification(eventName, event) {
  const repo = event.repository.full_name;
  if (!/^[\w.-]+\/[\w.-]+$/.test(repo)) throw new Error('Invalid repository.');
  const base = `https://github.com/${repo}`;
  let title, detail, url = base, color = 0x5865f2;
  switch (eventName) {
    case 'push':
      title = event.deleted ? '分支已删除' : '代码已推送';
      detail = `${event.ref} · ${event.head_commit?.message ?? ''}`;
      break;
    case 'pull_request_target':
      title = event.pull_request.merged ? 'PR 已合并' : `PR ${event.action}`;
      detail = `#${event.number} ${event.pull_request.title}`;
      url = `${base}/pull/${event.number}`;
      break;
    case 'issues':
    case 'issue_comment':
      title = eventName === 'issue_comment' ? '有新评论' : `Issue ${event.action}`;
      detail = `#${event.issue.number} ${event.issue.title}`;
      url = `${base}/issues/${event.issue.number}`;
      break;
    case 'workflow_run': {
      const run = event.workflow_run;
      if (!['CI', 'Publish Update Feed'].includes(run.name)) return null;
      const result = run.conclusion;
      const name = run.name === 'Publish Update Feed' ? '更新源同步' : run.name;
      title = `${name} ${event.action === 'in_progress' ? '已开始' : result}`;
      detail = `${run.head_branch} · ${String(run.head_sha).slice(0, 7)} · #${run.run_number}`;
      url = `${base}/actions/runs/${run.id}`;
      color = event.action === 'in_progress' ? color : result === 'success' ? 0x57f287 : result === 'failure' || result === 'timed_out' ? 0xed4245 : 0x99aab5;
      break;
    }
    case 'release':
      title = 'GitHub Release 已发布';
      detail = event.release.tag_name;
      url = `${base}/releases`;
      break;
    default: return null;
  }
  return {
    username: 'Buckle',
    allowed_mentions: { parse: [] },
    embeds: [{ title: `Buckle · ${escape(title)}`, description: `${escape(repo)}\n${escape(detail)}`, url, color }],
  };
}

export async function send(payload, webhook, fetcher = fetch) {
  let endpoint;
  try { endpoint = new URL(webhook); }
  catch { throw new Error('Invalid Discord webhook configuration.'); }
  if (endpoint.protocol !== 'https:' || !['discord.com', 'discordapp.com'].includes(endpoint.hostname) || !endpoint.pathname.startsWith('/api/webhooks/')) {
    throw new Error('Invalid Discord webhook configuration.');
  }
  endpoint.searchParams.set('wait', 'true');
  // Never let request errors include the credential-bearing URL.
  let response;
  try {
    response = await fetcher(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(10000),
    });
  } catch { throw new Error('Discord request failed.'); }
  if (!response.ok) throw new Error(`Discord returned HTTP ${response.status}.`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const event = JSON.parse(await readFile(process.env.GITHUB_EVENT_PATH, 'utf8'));
    const payload = notification(process.env.GITHUB_EVENT_NAME, event);
    if (payload) await send(payload, process.env.DISCORD_WEBHOOK_URL);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

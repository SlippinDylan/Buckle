import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const clean = value => String(value ?? '').replace(/\s+/g, ' ').slice(0, 240);
const escape = value => clean(value).replace(/([\\`*_~|<>@\[\]])/g, '\\$1');
const workflows = {
  CI: { label: '检查流程', job: 'Build Debug app' },
  Package: { label: '测试打包流程', job: 'Build DMG' },
  Release: { label: '正式发布流程', job: 'Publish GitHub Release' },
  'Publish Update Feed': { label: '更新源与 Homebrew 同步流程', job: 'Synchronize distribution metadata' },
};
const conclusions = {
  success: '成功', failure: '失败', cancelled: '已取消', timed_out: '超时',
  skipped: '已跳过', action_required: '需要人工处理', neutral: '无成功或失败结论', stale: '已过期',
};

function repository(event) {
  const name = event.repository.full_name;
  if (!/^[\w.-]+\/[\w.-]+$/.test(name)) throw new Error('Invalid repository.');
  return name;
}

function identifier(value) {
  if (!Number.isSafeInteger(value) || value <= 0) throw new Error('Invalid GitHub event identifier.');
  return value;
}

export function notification(eventName, event) {
  const repo = repository(event);
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
      url = `${base}/pull/${identifier(event.number)}`;
      break;
    case 'issues':
    case 'issue_comment': {
      const kind = event.issue.pull_request ? 'PR' : 'Issue';
      title = eventName === 'issue_comment' ? `${kind} 有新评论` : `${kind} ${event.action}`;
      detail = `#${event.issue.number} ${event.issue.title}`;
      url = `${base}/${kind === 'PR' ? 'pull' : 'issues'}/${identifier(event.issue.number)}`;
      break;
    }
    case 'pull_request_review':
    case 'pull_request_review_comment':
      title = eventName === 'pull_request_review_comment' ? 'PR 有代码评论' : `PR 审核：${event.review.state}`;
      detail = `#${event.pull_request.number} ${event.pull_request.title}`;
      url = `${base}/pull/${identifier(event.pull_request.number)}`;
      break;
    case 'workflow_run': {
      const run = event.workflow_run;
      if (!Object.hasOwn(workflows, run.name) || !['in_progress', 'completed'].includes(event.action)) return null;
      const started = event.action === 'in_progress';
      // Publication remains successful if requesting the separate distribution workflow fails later.
      const published = run.name === 'Release' && run.stageConclusion === 'success';
      const result = published ? 'success' : run.conclusion === 'success' && run.name !== 'CI' ? run.stageConclusion : run.conclusion;
      if (!started && !Object.hasOwn(conclusions, result)) throw new Error('Missing or unknown workflow stage conclusion.');
      title = `${workflows[run.name].label}${started ? '已开始' : `已结束：${conclusions[result]}`}`;
      detail = `${run.head_branch} · ${String(run.head_sha).slice(0, 7)} · #${run.run_number}`;
      if (!started && run.name === 'CI' && run.stageConclusion === 'skipped') detail += ' · App 编译已跳过';
      if (!started && run.name === 'Package' && run.stageConclusion !== 'success') detail += ' · 未确认生成安装包';
      if (!started && published) {
        detail += ' · GitHub Release 已发布，分发同步另行通知';
        if (run.distributionRequestConclusion && !['success', 'skipped'].includes(run.distributionRequestConclusion)) {
          detail += ` · 分发触发${conclusions[run.distributionRequestConclusion]}，可单独重跑`;
        }
        if (run.conclusion !== 'success') detail += ` · 整体流程${conclusions[run.conclusion]}`;
      }
      url = `${base}/actions/runs/${identifier(run.id)}`;
      color = started ? color : result === 'success' ? 0x57f287 : ['failure', 'timed_out'].includes(result) ? 0xed4245 : 0x99aab5;
      break;
    }
    case 'release':
      title = 'GitHub Release 已发布';
      detail = `${event.release.tag_name} · 更新源与 Homebrew 同步另行通知`;
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

export function stageStartNotification(name, environment) {
  if (!Object.hasOwn(workflows, name)) throw new Error('Unknown workflow stage.');
  if (!/^[a-f0-9]{40}$/.test(environment.GITHUB_SHA ?? '')) throw new Error('Invalid build commit SHA.');
  const runId = Number(environment.GITHUB_RUN_ID);
  identifier(runId);
  const repo = repository({ repository: { full_name: environment.GITHUB_REPOSITORY } });
  const labels = {
    CI: 'App 检查与编译', Package: '测试 App 与 DMG 构建', Release: 'GitHub Release 发布',
    'Publish Update Feed': '更新源与 Homebrew 同步',
  };
  return {
    username: 'Buckle',
    allowed_mentions: { parse: [] },
    embeds: [{
      title: `Buckle · ${labels[name]}阶段已开始`,
      description: `${escape(repo)}\n${escape(environment.GITHUB_REF_NAME)} · ${environment.GITHUB_SHA.slice(0, 7)}`,
      url: `https://github.com/${repo}/actions/runs/${runId}`,
      color: 0x5865f2,
    }],
  };
}

export async function enrichWorkflowResult(event, token, fetcher = fetch) {
  const run = event.workflow_run;
  if (event.action !== 'completed' || !Object.hasOwn(workflows, run.name)) return;
  if (!token) throw new Error('Missing Actions token for workflow result.');
  const endpoint = `https://api.github.com/repos/${repository(event)}/actions/runs/${identifier(run.id)}/attempts/${identifier(run.run_attempt)}/jobs?per_page=100`;
  let response;
  try {
    response = await fetcher(endpoint, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json' },
      signal: AbortSignal.timeout(10000), redirect: 'error',
    });
  } catch { throw new Error('Cannot read workflow jobs from GitHub.'); }
  if (!response.ok) throw new Error(`Cannot read workflow jobs: HTTP ${response.status}.`);
  const body = await response.json();
  if (!Array.isArray(body.jobs) || !Number.isSafeInteger(body.total_count) || body.total_count !== body.jobs.length || body.total_count > 100) {
    throw new Error('Incomplete workflow jobs response.');
  }
  const jobs = body.jobs.filter(job => job.name === workflows[run.name].job);
  // Early failures and cancellations can prevent the stage from being created.
  if (jobs.length === 0 && run.conclusion !== 'success') return;
  if (jobs.length !== 1 || !Object.hasOwn(conclusions, jobs[0].conclusion)) throw new Error('Expected exactly one completed workflow stage.');
  if (run.conclusion === 'success' && !['success', 'skipped', 'neutral'].includes(jobs[0].conclusion)) {
    throw new Error('Workflow success disagrees with its stage result.');
  }
  run.stageConclusion = jobs[0].conclusion;
  if (run.name === 'Release') {
    const requests = body.jobs.filter(job => job.name === 'Request distribution synchronization');
    if (requests.length > 1 || (requests.length === 1 && !Object.hasOwn(conclusions, requests[0].conclusion))) {
      throw new Error('Expected at most one completed distribution request stage.');
    }
    if (requests.length === 1) run.distributionRequestConclusion = requests[0].conclusion;
  }
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
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload), signal: AbortSignal.timeout(10000), redirect: 'error',
    });
  } catch { throw new Error('Discord request failed.'); }
  if (!response.ok) throw new Error(`Discord returned HTTP ${response.status}.`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    let payload;
    const arguments_ = process.argv.slice(2);
    if (arguments_.length) {
      if (arguments_.length !== 2 || arguments_[0] !== '--stage-start') {
        throw new Error('Use --stage-start <workflow name> or no arguments for webhook events.');
      }
      payload = stageStartNotification(arguments_[1], process.env);
    } else {
      const event = JSON.parse(await readFile(process.env.GITHUB_EVENT_PATH, 'utf8'));
      if (process.env.GITHUB_EVENT_NAME === 'workflow_run') await enrichWorkflowResult(event, process.env.GITHUB_TOKEN);
      payload = notification(process.env.GITHUB_EVENT_NAME, event);
    }
    if (payload) await send(payload, process.env.DISCORD_WEBHOOK_URL);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

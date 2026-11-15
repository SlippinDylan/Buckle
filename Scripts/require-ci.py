#!/usr/bin/env python3
"""Require a successful full CI run on the exact main commit before packaging."""

import json
import os
import subprocess


def select_run(runs, sha):
    eligible = [run for run in runs if run['headSha'] == sha
                and run['event'] in ('push', 'workflow_dispatch')]
    if not eligible or eligible[0]['conclusion'] != 'success':
        raise ValueError('The latest push/manual CI for this commit must succeed; run CI manually if needed')
    return eligible[0]['databaseId']


def check_jobs(body):
    builds = [job for job in body['jobs'] if job['name'] == 'Build Debug app']
    if body['total_count'] > 100 or len(builds) != 1 or builds[0]['conclusion'] != 'success':
        raise ValueError('This commit needs a successful Build Debug app job; run CI manually after skipped builds')


def gh(*args):
    return json.loads(subprocess.run(['gh', *args], check=True, capture_output=True, text=True).stdout)


def main():
    repo, sha = os.environ['GITHUB_REPOSITORY'], os.environ['GITHUB_SHA']
    runs = gh('run', 'list', '--repo', repo, '--workflow', 'ci.yml', '--branch', 'main',
              '--commit', sha, '--limit', '100', '--json', 'databaseId,event,conclusion,headSha')
    run_id = select_run(runs, sha)
    attempt = gh('api', 'repos/' + repo + '/actions/runs/' + str(run_id))['run_attempt']
    check_jobs(gh('api', 'repos/' + repo + '/actions/runs/' + str(run_id)
                  + '/attempts/' + str(attempt) + '/jobs?per_page=100'))
    print('Exact-commit CI and Build Debug app succeeded.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))

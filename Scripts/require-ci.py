#!/usr/bin/env python3
"""Require a successful full CI run on the exact main commit before packaging."""

import argparse
import json
import os
import subprocess


def select_run(runs, sha, source_run_id=None):
    eligible = [run for run in runs if run['headSha'] == sha
                and run['event'] in ('push', 'workflow_dispatch')
                and (source_run_id is None or run['databaseId'] == source_run_id)]
    if not eligible or eligible[0]['conclusion'] != 'success':
        raise ValueError('The selected push/manual CI for this commit must succeed; run CI manually if needed')
    return eligible[0]['databaseId']


def build_succeeded(body):
    builds = [job for job in body['jobs'] if job['name'] == 'Build Debug app']
    if body['total_count'] > 100 or len(builds) != 1 or builds[0]['conclusion'] not in ('success', 'skipped'):
        raise ValueError('Expected one completed Build Debug app job for this CI attempt')
    return builds[0]['conclusion'] == 'success'


def check_jobs(body):
    if not build_succeeded(body):
        raise ValueError('This commit needs a successful Build Debug app job; run CI manually after skipped builds')


def gh(*args):
    return json.loads(subprocess.run(['gh', *args], check=True, capture_output=True, text=True).stdout)


def main(allow_skipped=False):
    repo = os.environ['GITHUB_REPOSITORY']
    sha = os.environ['RELEASE_SHA'] if 'RELEASE_SHA' in os.environ else os.environ['GITHUB_SHA']
    runs = gh('run', 'list', '--repo', repo, '--workflow', 'ci.yml', '--branch', 'main',
              '--commit', sha, '--limit', '100', '--json', 'databaseId,event,conclusion,headSha')
    source_run_id = os.environ.get('SOURCE_CI_RUN_ID')
    run_id = select_run(runs, sha, int(source_run_id) if source_run_id else None)
    attempt = gh('api', 'repos/' + repo + '/actions/runs/' + str(run_id))['run_attempt']
    jobs = gh('api', 'repos/' + repo + '/actions/runs/' + str(run_id)
              + '/attempts/' + str(attempt) + '/jobs?per_page=100')
    built = build_succeeded(jobs)
    if not allow_skipped:
        check_jobs(jobs)
    if allow_skipped:
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write('build=' + str(built).lower() + '\n')
    print('Exact-commit CI passed; app build ' + ('succeeded.' if built else 'was skipped, so no automatic release.'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--allow-skipped', action='store_true', help='Report skipped builds without releasing them')
    args = parser.parse_args()
    try:
        main(args.allow_skipped)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))

import { appendFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export async function needsRelease(repository, version, token, fetcher = fetch) {
  const response = await fetcher(`https://api.github.com/repos/${repository}/releases/tags/v${version}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json' },
    signal: AbortSignal.timeout(10000),
  });
  if (response.status === 404) return true;
  if (!response.ok) throw new Error(`Cannot check release: HTTP ${response.status}.`);
  const release = await response.json();
  if (release.draft || release.prerelease) {
    throw new Error(`v${version} already exists as a draft or prerelease; resolve it before publishing.`);
  }
  return false;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const publish = await needsRelease(process.env.GH_REPO, process.env.VERSION, process.env.GH_TOKEN);
  await appendFile(process.env.GITHUB_OUTPUT, `publish=${publish}\n`);
  if (!publish) {
    await appendFile(process.env.GITHUB_STEP_SUMMARY,
      `v${process.env.VERSION} is already published. Its installer will not be replaced; increment the release manifest for a new version.\n`);
  }
}

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { verifyUpdateKey } from './update-key.mjs';

test('update signing requires the matching Ed25519 key pair', () => {
  const pair = generateKeyPairSync('ed25519');
  const seed = pair.privateKey.export({ format: 'der', type: 'pkcs8' }).subarray(-32).toString('base64');
  const publicKey = pair.publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
  verifyUpdateKey(seed, publicKey);
  assert.throws(() => verifyUpdateKey(seed, Buffer.alloc(32).toString('base64')));
  assert.throws(() => verifyUpdateKey('', publicKey));
  assert.throws(() => verifyUpdateKey(seed, 'invalid'));
  assert.throws(() => verifyUpdateKey(seed + '!', publicKey));
  const cli = spawnSync(process.execPath, ['.github/scripts/update-key.mjs'], {
    input: seed, encoding: 'utf8', env: { ...process.env, SPARKLE_PUBLIC_KEY: publicKey },
  });
  assert.equal(cli.status, 0, cli.stderr);
  assert.ok(!cli.stdout.includes(seed));
});

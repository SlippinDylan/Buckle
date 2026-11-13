import assert from 'node:assert/strict';
import { createPrivateKey, createPublicKey } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

export function verifyUpdateKey(privateKey, publicKey) {
  const seed = Buffer.from(privateKey.trim(), 'base64');
  const expected = Buffer.from(publicKey.trim(), 'base64');
  assert.ok(seed.toString('base64') === privateKey.trim(), 'Invalid private-key encoding.');
  assert.ok(expected.toString('base64') === publicKey.trim(), 'Invalid public-key encoding.');
  assert.equal(seed.length, 32, 'Expected a Sparkle Ed25519 private seed.');
  assert.equal(expected.length, 32, 'Expected an Ed25519 public key.');
  const key = createPrivateKey({
    key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]),
    format: 'der', type: 'pkcs8',
  });
  const derived = createPublicKey(key).export({ format: 'der', type: 'spki' }).subarray(-32);
  assert.ok(derived.equals(expected), 'Sparkle signing key does not match the app public key.');
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  try {
    process.stdin.setEncoding('utf8');
    let privateKey = '';
    for await (const chunk of process.stdin) privateKey += chunk;
    verifyUpdateKey(privateKey, process.env.SPARKLE_PUBLIC_KEY ?? '');
    console.log('Sparkle update signing key pair verified.');
  } catch {
    console.error('Sparkle key verification failed. Check the private seed and app public key.');
    process.exitCode = 1;
  }
}

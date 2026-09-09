import { createPrivateKey, createPublicKey, sign, createHash } from 'node:crypto';

export function signingKey(seedBase64, expectedPublicBase64) {
  const seed = Buffer.from(seedBase64, 'base64');
  if (seed.length !== 32) throw new Error('Invalid licence signing key');
  const key = createPrivateKey({
    key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]),
    format: 'der', type: 'pkcs8',
  });
  const publicBytes = createPublicKey(key).export({ format: 'der', type: 'spki' }).subarray(-32);
  if (!expectedPublicBase64 || publicBytes.toString('base64') !== expectedPublicBase64) {
    throw new Error('Licence key does not match the public key shipped in the app');
  }
  return key;
}

// Retries, landing-page requests and webhooks produce the same licence, even
// after restoring the database. No customer identity is embedded in the key.
export function issueLicense({ session, key, keyID }) {
  const payload = {
    entitlement: 'founder',
    issuedAt: new Date(session.created * 1000).toISOString().replace('.000Z', 'Z'),
    keyID,
    licenseID: createHash('sha256').update(`PressTalk-order-v1:${session.id}`).digest('hex'),
    maxMajorVersion: 0,
    productID: 'com.am.presstalk',
    schemaVersion: 1,
  };
  const encoded = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = sign(null, Buffer.from(`PressTalk-license-v1\n${keyID}.${encoded}`), key);
  return `PRESSTALK-1.${keyID}.${encoded}.${signature.toString('base64url')}`;
}

export function activationURL(license) {
  return `presstalk://activate?license=${encodeURIComponent(license)}`;
}

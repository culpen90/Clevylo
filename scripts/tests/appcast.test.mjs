import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import test from 'node:test';
import { feedURL, verifyAppcast } from '../verify-appcast.mjs';

function fixture(change = {}) {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const archive = Buffer.from('a fixture standing in for the exact published archive bytes');
  const signature = sign(null, archive, privateKey).toString('base64');
  const publicRaw = publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
  const values = {
    version: '1.2.3', build: '42', minimumOS: '14.0', length: archive.length, signature,
    url: 'https://github.com/culpen90/Clevylo/releases/download/v1.2.3/Clevylo-1.2.3-macOS-universal.zip',
    ...change,
  };
  const content = Buffer.from(`<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel><title>Clevylo</title><item>
    <sparkle:version>${values.build}</sparkle:version>
    <sparkle:shortVersionString>${values.version}</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>${values.minimumOS}</sparkle:minimumSystemVersion>
    <enclosure url="${values.url}" length="${values.length}" type="application/octet-stream" sparkle:edSignature="${values.signature}"/>
  </item></channel>
</rss>
`);
  const feedSignature = sign(null, content, privateKey).toString('base64');
  const appcast = Buffer.concat([content, Buffer.from(`<!-- sparkle-signatures:\nedSignature: ${feedSignature}\nlength: ${content.length}\n-->\n`)]);
  return {
    appcast, archive, version: '1.2.3', build: '42',
    info: {
      SUPublicEDKey: publicRaw, SUFeedURL: feedURL,
      SURequireSignedFeed: true, SUVerifyUpdateBeforeExtraction: true,
      CFBundleShortVersionString: '1.2.3', CFBundleVersion: '42',
    },
  };
}

test('signed feed and archive validate against the public key embedded in the app', () => {
  assert.doesNotThrow(() => verifyAppcast(fixture()));
});

test('an altered archive is rejected even when its length is unchanged', () => {
  const input = fixture();
  input.archive[0] ^= 1;
  assert.throws(() => verifyAppcast(input), /Archive signature/);
});

test('altered feed metadata is rejected before XML is trusted', () => {
  const input = fixture();
  input.appcast = Buffer.from(input.appcast.toString().replace('Clevylo</title>', 'clevylo</title>'));
  assert.throws(() => verifyAppcast(input), /Feed signature/);
});

test('the wrong signing key cannot publish updates to installed apps', () => {
  const input = fixture();
  input.info.SUPublicEDKey = fixture().info.SUPublicEDKey;
  assert.throws(() => verifyAppcast(input), /Feed signature/);
});

test('unsigned appcast and appended content are rejected', () => {
  const input = fixture();
  const end = input.appcast.indexOf('<!-- sparkle-signatures:');
  assert.throws(() => verifyAppcast({ ...input, appcast: input.appcast.subarray(0, end) }), /missing its feed signature/);
  assert.throws(() => verifyAppcast({ ...input, appcast: Buffer.concat([input.appcast, Buffer.from('\n')]) }), /Invalid Sparkle/);
});

for (const [change, message] of [
  [{ version: '1.2.4' }, /Feed version/],
  [{ build: '43' }, /Feed build number/],
  [{ minimumOS: '15.0' }, /minimum macOS/],
  [{ length: 1 }, /Archive length/],
  [{ signature: '' }, /invalid Ed25519/],
  [{ url: 'https://github.com/culpen90/Clevylo/releases/latest/download/Clevylo-macOS-universal.zip' }, /immutable release/],
  [{ url: 'https://example.com/update.zip' }, /immutable release/],
]) {
  test(`signed but inconsistent feed metadata is rejected: ${JSON.stringify(change)}`, () => {
    assert.throws(() => verifyAppcast(fixture(change)), message);
  });
}

for (const [key, value] of [
  ['SURequireSignedFeed', false],
  ['SUVerifyUpdateBeforeExtraction', false],
  ['SUFeedURL', 'http://example.com/appcast.xml'],
]) {
  test(`release rejects unsafe app setting ${key}`, () => {
    const input = fixture();
    input.info[key] = value;
    assert.throws(() => verifyAppcast(input));
  });
}

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createPublicKey, verify } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryURL = 'https://github.com/culpen90/Clevylo';
export const feedURL = `${repositoryURL}/releases/latest/download/appcast.xml`;

// Use the standard XML parser instead of extracting enclosure attributes with
// regular expressions. Only the final Sparkle signing comment is byte parsed:
// its signature covers the exact preceding bytes, including whitespace.
function parseFeed(content) {
  return JSON.parse(execFileSync('python3', ['-c', `
import json, sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.buffer.read())
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
items = root.findall("./channel/item")
if root.tag != "rss" or len(items) != 1:
    raise SystemExit("Expected exactly one stable release in the appcast")
item = items[0]
enclosures = item.findall("enclosure")
if len(enclosures) != 1:
    raise SystemExit("Expected exactly one full update archive")
print(json.dumps({
    "version": item.findtext("sparkle:version", namespaces=ns),
    "shortVersion": item.findtext("sparkle:shortVersionString", namespaces=ns),
    "minimumOS": item.findtext("sparkle:minimumSystemVersion", namespaces=ns),
    "enclosure": enclosures[0].attrib,
}))
`], { input: content, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }));
}

function signatureBytes(value) {
  assert.match(value ?? '', /^[A-Za-z0-9+/]{86}==$/, 'Missing or invalid Ed25519 signature');
  const signature = Buffer.from(value, 'base64');
  assert.equal(signature.length, 64);
  return signature;
}

export function verifyAppcast({ appcast, archive, info, version, build }) {
  assert.equal(info.SUFeedURL, feedURL, 'Release must use the stable HTTPS appcast');
  assert.equal(info.SURequireSignedFeed, true, 'The app must require signed feeds');
  assert.equal(info.SUVerifyUpdateBeforeExtraction, true, 'The app must verify archives before extraction');
  assert.equal(info.CFBundleShortVersionString, version);
  assert.equal(info.CFBundleVersion, build);
  assert.match(info.SUPublicEDKey ?? '', /^[A-Za-z0-9+/]{43}=$/, 'Missing or invalid update public key');
  const publicKey = createPublicKey({
    key: Buffer.concat([
      Buffer.from('302a300506032b6570032100', 'hex'),
      Buffer.from(info.SUPublicEDKey, 'base64'),
    ]),
    format: 'der',
    type: 'spki',
  });

  // Sparkle 2.10's signAppcast appends this block to the signed XML bytes.
  const marker = Buffer.from('<!-- sparkle-signatures:\n');
  const markerOffset = appcast.lastIndexOf(marker);
  assert.ok(markerOffset > 0, 'Appcast is missing its feed signature');
  const signingBlock = appcast.subarray(markerOffset).toString('ascii');
  const fields = /^<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->\n$/.exec(signingBlock);
  assert.ok(fields, 'Invalid Sparkle feed signature block');
  const signedContent = appcast.subarray(0, markerOffset);
  assert.equal(Number(fields[2]), signedContent.length, 'Signed feed length does not match');
  assert.ok(verify(null, signedContent, publicKey, signatureBytes(fields[1])), 'Feed signature does not match the app public key');

  const feed = parseFeed(signedContent);
  const signatureKey = '{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature';
  assert.equal(feed.version, build, 'Feed build number does not match the app');
  assert.equal(feed.shortVersion, version, 'Feed version does not match the app');
  assert.match(feed.minimumOS ?? '', /^14\.0(?:\.0)?$/, 'Unexpected minimum macOS version');
  assert.equal(feed.enclosure.url, `${repositoryURL}/releases/download/v${version}/Clevylo-${version}-macOS-universal.zip`, 'Update URL must name this immutable release archive');
  assert.equal(feed.enclosure.type, 'application/octet-stream');
  assert.equal(feed.enclosure.length, String(archive.length), 'Archive length does not match');
  assert.ok(verify(null, archive, publicKey, signatureBytes(feed.enclosure[signatureKey])), 'Archive signature does not match the app public key');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [appcastPath, archivePath, appPath, version, build, ...extra] = process.argv.slice(2);
  if (!build || extra.length) {
    throw new Error('Usage: node scripts/verify-appcast.mjs APPCAST ARCHIVE APP_BUNDLE VERSION BUILD_NUMBER');
  }
  const info = JSON.parse(execFileSync('python3', ['-c',
    'import json, plistlib, sys; print(json.dumps(plistlib.load(open(sys.argv[1], "rb"))))',
    `${appPath}/Contents/Info.plist`,
  ], { encoding: 'utf8' }));
  verifyAppcast({ appcast: readFileSync(appcastPath), archive: readFileSync(archivePath), info, version, build });
  console.log(`Verified signed appcast and update archive for Clevylo ${version} (build ${build}).`);
}

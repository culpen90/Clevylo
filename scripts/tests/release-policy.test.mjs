import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { analyzeCommits } from '@semantic-release/commit-analyzer';
import { generateNotes } from '@semantic-release/release-notes-generator';

const configuration = JSON.parse(
  await readFile(new URL('../../.releaserc.json', import.meta.url), 'utf8'),
);
const logger = { log() {}, error() {}, success() {} };

function optionsFor(pluginName) {
  const entry = configuration.plugins.find((plugin) =>
    (Array.isArray(plugin) ? plugin[0] : plugin) === pluginName,
  );
  assert.ok(entry, `The release configuration must include ${pluginName}`);
  return Array.isArray(entry) ? entry[1] : {};
}

function commitsFor(messages) {
  return messages.map((message, index) => ({
    message,
    hash: (index + 1).toString(16).padStart(40, '0'),
  }));
}

async function releaseType(...messages) {
  return analyzeCommits(optionsFor('@semantic-release/commit-analyzer'), {
    cwd: process.cwd(),
    commits: commitsFor(messages),
    logger,
  });
}

for (const [message, expected] of [
  ['fix: recover from a missing study folder', 'patch'],
  ['fix(import): accept empty attachments', 'patch'],
  ['perf: reduce document indexing time', 'patch'],
  ['perf(search): reuse the search index', 'patch'],
  ['feat: add a study timer', 'minor'],
  ['feat(homework): group assignments by class', 'minor'],
  ['feat!: replace the study session format', 'major'],
  ['fix(storage)!: reject the obsolete database format', 'major'],
  ['chore!: require a newer macOS version', 'major'],
  ['feat: replace settings\n\nBREAKING CHANGE: Settings now use a nested object.', 'major'],
  ['fix: revise imports\n\nBREAKING-CHANGE: Legacy import files are no longer accepted.', 'major'],
  ['docs: explain how to open a study folder', null],
  ['chore: tidy the repository', null],
  ['build: update the packaging script', null],
  ['ci: update the test workflow', null],
  ['test: cover empty study sessions', null],
  ['Update the study timer', null],
  ['feat add a study timer', null],
  ['fix(scope) accept empty attachments', null],
]) {
  test(`${JSON.stringify(message)} selects ${expected ?? 'no release'}`, async () => {
    assert.equal(await releaseType(message), expected);
  });
}

test('an empty commit range does not release', async () => {
  assert.equal(await releaseType(), null);
});

test('a range containing only maintenance commits does not release', async () => {
  assert.equal(
    await releaseType('docs: revise help', 'ci: cache the build', 'chore: tidy formatting'),
    null,
  );
});

test('a feature wins over fixes and maintenance in either commit order', async () => {
  const messages = ['fix: restore keyboard focus', 'feat: add a study timer', 'docs: revise help'];
  assert.equal(await releaseType(...messages), 'minor');
  assert.equal(await releaseType(...messages.toReversed()), 'minor');
});

test('a breaking change wins over features and fixes in either commit order', async () => {
  const messages = [
    'feat: add a study timer',
    'fix: restore keyboard focus',
    'build!: require the new packaging layout',
  ];
  assert.equal(await releaseType(...messages), 'major');
  assert.equal(await releaseType(...messages.toReversed()), 'major');
});

test('release notes include user changes, breaking migration guidance, and GitHub links', async () => {
  const notes = await generateNotes(optionsFor('@semantic-release/release-notes-generator'), {
    cwd: process.cwd(),
    env: {},
    options: {
      repositoryUrl: 'https://github.com/example/release-fixture.git',
      tagFormat: configuration.tagFormat,
    },
    lastRelease: { version: '1.4.0', gitTag: 'v1.4.0' },
    nextRelease: { version: '2.0.0', gitTag: 'v2.0.0' },
    commits: commitsFor([
      'feat(study): add a study timer',
      'fix(import): accept empty attachments (#42)',
      'feat!: replace settings\n\nBREAKING CHANGE: Move preferences into the settings object.',
      'docs: internal documentation housekeeping',
    ]),
    logger,
  });

  assert.match(notes, /2\.0\.0/);
  assert.match(notes, /Features/);
  assert.match(notes, /Bug Fixes/);
  assert.match(notes, /BREAKING CHANGES/);
  assert.match(notes, /add a study timer/);
  assert.match(notes, /accept empty attachments/);
  assert.match(notes, /Move preferences into the settings object\./);
  assert.match(notes, /https:\/\/github\.com\/example\/release-fixture\/compare\/v1\.4\.0\.\.\.v2\.0\.0/);
  assert.match(notes, /https:\/\/github\.com\/example\/release-fixture\/commit\/0000000000000000000000000000000000000001/);
  assert.match(notes, /https:\/\/github\.com\/example\/release-fixture\/issues\/42/);
  assert.doesNotMatch(notes, /internal documentation housekeeping/);
});

test('GitHub asset resolution selects both archives and checksums without unrelated files', async (context) => {
  const fixtureRoot = await mkdtemp(join(tmpdir(), 'clevylo-release-assets-'));
  context.after(() => rm(fixtureRoot, { recursive: true, force: true }));
  const outputDirectory = join(fixtureRoot, 'build/release');
  await mkdir(outputDirectory, { recursive: true });
  const expectedAssets = [
    'Clevylo-1.2.3-macOS-universal.zip',
    'Clevylo-macOS-universal.zip',
    'SHA256SUMS',
  ];
  await Promise.all(
    [...expectedAssets, 'Clevylo-symbols.zip', 'Clevylo-preview-macOS-universal.zip', 'build.log']
      .map((name) => writeFile(join(outputDirectory, name), 'local asset fixture\n')),
  );

  // Exercise the installed plugin's resolver: asset paths are globbed directly,
  // while only their names and labels support nextRelease template expressions.
  const { default: globAssets } = await import(
    new URL('./lib/glob-assets.js', import.meta.resolve('@semantic-release/github'))
  );
  const resolved = await globAssets(
    { cwd: fixtureRoot, nextRelease: { version: '1.2.3' } },
    optionsFor('@semantic-release/github').assets,
  );

  assert.deepEqual(
    resolved.map((asset) => (typeof asset === 'string' ? asset : asset.path)).sort(),
    expectedAssets.map((name) => `build/release/${name}`).sort(),
  );
});

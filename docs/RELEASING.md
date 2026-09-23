# Automatic GitHub releases

The [Test and release workflow](../.github/workflows/release.yml) uses [semantic-release](https://github.com/semantic-release/semantic-release) to publish stable releases from `main`, continuing from the existing `v1.0.0` tag. It requires no additional secrets: GitHub supplies a repository-scoped `GITHUB_TOKEN`. Only the publishing job has `contents: write`; pull requests run tests with read-only permissions.

## Choosing versions

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). When squash merging, make the **PR title** the desired commit subject and retain any breaking-change footer in the squash commit body.

| Commit | Release from 1.2.3 |
| --- | --- |
| `fix: prevent duplicate materials` | 1.2.4 |
| `perf(search): reduce indexing time` | 1.2.4 |
| `feat: add a study timer` | 1.3.0 |
| `feat!: change the library format` | 2.0.0 |
| Any type with a `BREAKING CHANGE:` or `BREAKING-CHANGE:` footer | 2.0.0 |
| `docs:`, `test:`, `chore:`, `ci:`, `build:`, or unformatted commits | No release, unless marked breaking |

The highest bump among all commits since the last release wins. Scope is optional. A push with no release-worthy commits succeeds without creating a version. Use `fix:` when a packaging or dependency change fixes behavior users receive; ordinary maintenance can use `chore:`. Tags are the release version source of truth; do not manually create the next tag before running the bot.

## What the bot does

1. Runs release-policy and release-notes tests against the installed tooling, then macOS unit tests. These checks also run for pull requests.
2. On `main`, determines the next version from the complete Git history. Runs are serialized to avoid competing version calculations. A checkout already behind `main` when the initial release check runs is skipped; changes pushed during packaging are handled by a subsequent run.
3. Builds with Xcode 26.6 on a `macos-26` runner. The release version overrides `MARKETING_VERSION`; the number of commits at that source revision supplies `CURRENT_PROJECT_VERSION`. The checked-in Xcode project and `project.yml` keep their development defaults, so no version-bump commit or release loop is needed.
4. Ad-hoc signs the app and verifies the **extracted ZIP**, including its version, build number, macOS minimum, arm64 and x86_64 slices, signature, and absence of debug entitlements or test bundles. A build or verification failure stops before tagging.
5. Tags that exact source commit, creates a GitHub draft, uploads the archives and checksums, then publishes the release with generated notes and installation guidance. The release tooling does not post issue/PR comments or publish anything to npm.

Each release contains:

- `Clevylo-VERSION-macOS-universal.zip`: the versioned app download.
- `Clevylo-macOS-universal.zip`: an identical copy providing a permanent [latest download link](https://github.com/culpen90/Clevylo/releases/latest/download/Clevylo-macOS-universal.zip).
- `SHA256SUMS`: checksums for both ZIP files.

Packaging and publishing run in the same workflow because [events created with `GITHUB_TOKEN` do not normally trigger another workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow). Node dependencies are pinned in `package-lock.json`, and third-party actions use immutable commit SHAs. Node is development tooling only and is not included in the app.

## Previewing and retrying

Open **Actions → Test and release → Run workflow**, select **main**, and leave **dry_run** checked to preview the next version and notes. Uncheck it to retry publication after a transient failure; the same tests still run. A normal push to `main` publishes automatically. Manual runs from other branches never publish.

For local tooling checks (Node 24.10 or newer within Node 24):

```sh
npm ci --ignore-scripts
npm test
```

To preview locally, `npm run release:preview -- --no-ci` also needs a GitHub credential with repository access. Keep credentials in your environment; do not put them in tracked files. A dry run skips packaging and publication, so it does not prove the app builds.

If publication fails **after the tag was pushed**, semantic-release considers that version released and will not automatically recreate it. Preserve the tag and inspect the run and any draft on the Releases page. The workflow retains packaged files as `release-packages-SOURCE_SHA` for 30 days. Download that artifact, verify `SHA256SUMS`, upload any missing files to the existing draft, then publish it. If the draft was never created, create a release against the existing tag using those verified assets and the generated notes from the run. Do not move or delete a published tag, or publish files from a different source revision under it. If packaging failed before tagging, fix the problem and rerun the workflow normally.

## Reproducing an archive

On a Mac with Xcode, check out the desired release tag and use its version and commit count:

```sh
./scripts/test.sh --unit
release_version="$(git describe --tags --exact-match | sed 's/^v//')"
release_build_number="$(git rev-list --count HEAD)"
./scripts/package-release.sh "$release_version" "$release_build_number"
(cd build/release && shasum -a 256 -c SHA256SUMS)
```

The first manually packaged `v1.0.0` used build number 1; subsequent bot releases use the commit count. Builds from different Xcode versions need not have identical checksums. `./scripts/build.sh` still creates `build/Clevylo.zip` for local development. Optional `CLEVYLO_VERSION` and `CLEVYLO_BUILD_NUMBER` environment variables override its bundle metadata without editing the project.

## Signing and installation

Releases are ad-hoc signed, **not Developer ID signed or notarized**. Signature verification does not establish Gatekeeper approval. After the first attempted launch, users may need **System Settings → Privacy & Security → Open Anyway** for this specific app. Follow [Apple's guidance](https://support.apple.com/en-us/102445); managed computers may prohibit this exception.

Expand the ZIP, move the app to Applications, and open it. Updates are installed manually. Quit Clevylo before replacing an installed copy. The library remains separately in `~/Library/Application Support/Clevylo/`. Checksums verify integrity, not an independent developer signature.

## Verification limits

The bot gates publication on release-policy tests, macOS unit tests, and archive verification. GUI smoke tests (`./scripts/test.sh --ui`) require a macOS GUI automation session and remain a manual release check. Universal packaging does not prove execution on Intel hardware or macOS 14. Live inference needs an installed Ollama model or the user's OpenRouter key and remains a separate check. No model, credential, or student library is bundled. See [the verification record](VERIFICATION.md) for the original app's local test evidence.

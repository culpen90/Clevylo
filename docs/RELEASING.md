# Automatic GitHub releases

The [Test and release workflow](../.github/workflows/release.yml) uses [semantic-release](https://github.com/semantic-release/semantic-release) to publish stable releases from `main`, continuing from the existing `v1.0.0` tag. GitHub supplies a repository-scoped `GITHUB_TOKEN`; the repository's `SPARKLE_PRIVATE_KEY` Actions secret signs in-app updates. Only the publishing job has `contents: write` or receives that signing secret; pull requests run tests with read-only permissions. No paid Apple developer account is required.

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
3. Builds with Xcode 26.6 on a `macos-26` runner. The release version overrides `MARKETING_VERSION`; the number of commits at that source revision supplies `CURRENT_PROJECT_VERSION`. Sparkle compares that build number to find newer versions. Keep `main` history intact so the count increases; never reset it or change to a lower numbering scheme. The checked-in Xcode project and `project.yml` keep their development defaults, so no version-bump commit or release loop is needed.
4. Ad-hoc signs the app while retaining Sparkle's original helper signatures and entitlements and re-signing the outer framework after Xcode strips its headers. Verifies the **extracted ZIP**, including its version, build number, macOS minimum, arm64 and x86_64 slices, signatures, and absence of debug entitlements or test bundles.
5. Uses the tools from the exact Sparkle package pinned by the app to generate `appcast.xml`. Signs both the update archive and feed with Ed25519. Independently verifies both signatures against the public key inside the extracted app, and checks the feed's version, size, minimum OS, and immutable download URL. Missing keys, mismatched keys, and unsigned feeds stop publication before tagging.
6. Tags that exact source commit, creates a GitHub draft, uploads the archives, signed feed, and checksums, then publishes the release with generated notes and installation guidance. Publishing the draft makes all assets available together. The release tooling does not post issue/PR comments or publish anything to npm.

Each release contains:

- `Clevylo-VERSION-macOS-universal.zip`: the versioned app download.
- `Clevylo-macOS-universal.zip`: an identical copy providing a permanent [latest download link](https://github.com/culpen90/Clevylo/releases/latest/download/Clevylo-macOS-universal.zip).
- `appcast.xml`: a signed Sparkle feed at the permanent [latest update feed URL](https://github.com/culpen90/Clevylo/releases/latest/download/appcast.xml). Its enclosure points to the versioned ZIP under the exact release tag, so an update check cannot download a different release when `latest` advances.
- `SHA256SUMS`: checksums for both ZIP files and the signed feed.

The feed contains the current full update only; no delta patches or separate hosted service are needed. Release history is available through its full-release-notes link. The feed becomes available with the first release containing this feature. Earlier versions need one manual installation to gain in-app updates.

Packaging and publishing run in the same workflow because [events created with `GITHUB_TOKEN` do not normally trigger another workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow). Node dependencies are pinned in `package-lock.json`, and third-party actions use immutable commit SHAs. Node is development tooling only and is not included in the app.

## Previewing and retrying

Open **Actions → Test and release → Run workflow**, select **main**, and leave **dry_run** checked to preview the next version and notes. Uncheck it to retry publication after a transient failure; the same tests still run. A normal push to `main` publishes automatically. Manual runs from other branches never publish.

For local tooling checks (Node 24.10 or newer within Node 24):

```sh
npm ci --ignore-scripts
npm test
```

To preview locally, `npm run release:preview -- --no-ci` also needs a GitHub credential with repository access. Keep credentials in your environment; do not put them in tracked files. A dry run skips packaging and publication, so it does not prove the app builds.

If publication fails **after the tag was pushed**, semantic-release considers that version released and will not automatically recreate it. Preserve the tag and inspect the run and any draft on the Releases page. The workflow retains packaged files as `release-packages-SOURCE_SHA` for 30 days. Download that artifact, verify `SHA256SUMS`, upload any missing files (including `appcast.xml`) to the existing draft, then publish it. If the draft was never created, create a release against the existing tag using those verified assets and the generated notes from the run. Do not edit a signed feed: changing even whitespace invalidates its signature. Do not move or delete a published tag, or publish files from a different source revision under it. If packaging failed before tagging, fix the problem and rerun the workflow normally.

## Reproducing an archive

On a Mac with Xcode, check out the desired release tag and use its version and commit count:

```sh
./scripts/test.sh --unit
release_version="$(git describe --tags --exact-match | sed 's/^v//')"
release_build_number="$(git rev-list --count HEAD)"
SPARKLE_KEYCHAIN_ACCOUNT=com.clevylo.app.updates \
  ./scripts/package-release.sh "$release_version" "$release_build_number"
(cd build/release && shasum -a 256 -c SHA256SUMS)
```

The first manually packaged `v1.0.0` used build number 1; subsequent bot releases use the commit count. Builds from different Xcode versions need not have identical checksums. `./scripts/build.sh` still creates `build/Clevylo.zip` for local development and needs no signing secret. Optional `CLEVYLO_VERSION` and `CLEVYLO_BUILD_NUMBER` environment variables override its bundle metadata without editing the project. Packaging additionally needs Node and the existing update signing key.

If a synced folder repeatedly adds Finder metadata during signing, set an absolute `CLEVYLO_BUILD_DIR` outside that folder (for example `/tmp/clevylo-build`) for building, testing, and packaging. Derived data, Sparkle tools, and `Clevylo.zip` follow that location. Final publication assets remain in the checkout's `build/release/`.

## Update signing key

`Clevylo/Info.plist` contains the public `SUPublicEDKey`. The private key is stored in the maintainer's login Keychain under the dedicated `com.clevylo.app.updates` account, and in the repository's `SPARKLE_PRIVATE_KEY` Actions secret. The workflow passes it only to the publishing step; signing tools read it over standard input rather than process arguments or checkout files. Do not paste the key into logs, commit it, or attach it as an artifact.

For a new maintainer or recovered key, use Sparkle's `generate_keys` tool in `build/SourcePackages/artifacts/sparkle/Sparkle/bin/` after resolving the package. Its `--account`, `-x` (export), and `-f` (import) options manage the dedicated Keychain item. Export only into a protected temporary location for an encrypted backup or secret transfer, and remove that temporary file immediately. Keep a secure backup: an ad-hoc signed app cannot receive updates signed by an unrelated replacement key. Do not regenerate the key for routine releases. See [Sparkle's signing instructions](https://sparkle-project.org/documentation/#3-segue-for-security-concerns).

The app requires a signed feed and verifies the signed archive before extraction. Automatic checks are optional; downloading and installing an update requires the user's action. Sparkle presents download progress, install/relaunch controls, and recoverable errors through its native macOS update window.

## Signing and installation

Releases are ad-hoc signed, **not Developer ID signed or notarized**. Signature verification does not establish Gatekeeper approval. After the first attempted launch, users may need **System Settings → Privacy & Security → Open Anyway** for this specific app. Follow [Apple's guidance](https://support.apple.com/en-us/102445); managed computers may prohibit this exception.

For the first installation, expand the ZIP, move the app to Applications, and open it. Afterwards choose **Clevylo → Check for Updates…** or **Settings → Updates**, then use the update window to download, install, and relaunch. The library remains separately in `~/Library/Application Support/Clevylo/`. Update authenticity comes from the Ed25519 key shipped with the app; this does not grant Apple notarization or Gatekeeper approval for the first installation. Checksums alone are not an independent developer signature.

## Verification limits

The bot gates publication on release-policy and signed-feed tests, macOS unit tests, archive verification, and cryptographic verification of the generated update. Feed tests cover tampered archives, tampered metadata, wrong keys, missing signatures, incorrect versions, and incorrect download URLs. GUI smoke tests (`./scripts/test.sh --ui`) and an actual installation/relaunch between two signed builds require a macOS GUI session and remain manual release checks. A successful local update test does not establish that a new GitHub release has been published or that its live feed is reachable. Universal packaging does not prove execution on Intel hardware or macOS 14. Live inference needs an installed Ollama model or the user's OpenRouter key and remains a separate check. No model, credential, or student library is bundled. See [the verification record](VERIFICATION.md) for the original app's local test evidence.

#!/bin/bash
set -euo pipefail

workspace_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${CLEVYLO_BUILD_DIR:-$workspace_dir/build}"
if [[ "$build_dir" != /* ]]; then
  printf 'CLEVYLO_BUILD_DIR must be an absolute path.\n' >&2
  exit 2
fi
if [[ "$#" -ne 5 ]]; then
  printf 'Usage: %s VERSION BUILD_NUMBER ARCHIVE APP_BUNDLE OUTPUT\n' "$0" >&2
  exit 2
fi
release_version="$1"
release_build_number="$2"
release_archive="$3"
app_bundle="$4"
output_path="$5"
if [[ ! "$release_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || \
   [[ ! "$release_build_number" =~ ^[1-9][0-9]*$ ]]; then
  printf 'A stable semantic version and positive build number are required.\n' >&2
  exit 2
fi
if [[ -z "${SPARKLE_PRIVATE_KEY:-}" && -z "${SPARKLE_KEYCHAIN_ACCOUNT:-}" ]]; then
  printf 'Set SPARKLE_PRIVATE_KEY for CI or SPARKLE_KEYCHAIN_ACCOUNT for local update signing.\n' >&2
  exit 1
fi

# These tools arrive in the checksum-verified binary artifact for the exact
# Sparkle package version pinned by the app, rather than a separate download.
sparkle_bin="$build_dir/SourcePackages/artifacts/sparkle/Sparkle/bin"
if [[ ! -x "$sparkle_bin/generate_appcast" ]]; then
  printf 'Sparkle tools are missing; build the app to resolve its pinned package first.\n' >&2
  exit 1
fi
feed_directory="$(mktemp -d "${TMPDIR:-/tmp}/clevylo-appcast.XXXXXX")"
trap 'rm -rf "$feed_directory"' EXIT
archive_name="Clevylo-$release_version-macOS-universal.zip"
cp "$release_archive" "$feed_directory/$archive_name"
signing_arguments=(--account "${SPARKLE_KEYCHAIN_ACCOUNT:-com.clevylo.app.updates}")
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then signing_arguments=(--ed-key-file -); fi

# Only one archive is present, so the feed cannot accidentally select a stale
# release or the duplicate stable-download ZIP. No delta assets are generated.
generator_arguments=("${signing_arguments[@]}" --maximum-deltas 0
  --download-url-prefix "https://github.com/culpen90/Clevylo/releases/download/v$release_version/"
  --full-release-notes-url "https://github.com/culpen90/Clevylo/releases/tag/v$release_version"
  --link "https://github.com/culpen90/Clevylo"
  -o "$feed_directory/appcast.xml" "$feed_directory")
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  # The key is sent on stdin, never a process argument or a file in the checkout.
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sparkle_bin/generate_appcast" "${generator_arguments[@]}"
else
  "$sparkle_bin/generate_appcast" "${generator_arguments[@]}"
fi
node "$workspace_dir/scripts/verify-appcast.mjs" "$feed_directory/appcast.xml" \
  "$feed_directory/$archive_name" "$app_bundle" "$release_version" "$release_build_number"
cp "$feed_directory/appcast.xml" "$output_path"

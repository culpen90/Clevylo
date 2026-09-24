#!/bin/bash
set -euo pipefail

workspace_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${CLEVYLO_BUILD_DIR:-$workspace_dir/build}"
if [[ "$build_dir" != /* ]]; then
  printf 'CLEVYLO_BUILD_DIR must be an absolute path.\n' >&2
  exit 2
fi
cd "$workspace_dir"
if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s VERSION BUILD_NUMBER\n' "$0" >&2
  exit 2
fi
release_version="$1"
release_build_number="$2"
if [[ ! "$release_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  printf 'VERSION must be a stable semantic version, such as 1.2.3.\n' >&2
  exit 2
fi
if [[ ! "$release_build_number" =~ ^[1-9][0-9]*$ ]]; then
  printf 'BUILD_NUMBER must be a positive integer.\n' >&2
  exit 2
fi
if [[ -z "${SPARKLE_PRIVATE_KEY:-}" && -z "${SPARKLE_KEYCHAIN_ACCOUNT:-}" ]]; then
  printf 'Set SPARKLE_PRIVATE_KEY for CI or SPARKLE_KEYCHAIN_ACCOUNT for local update signing.\n' >&2
  exit 1
fi

env -u SPARKLE_PRIVATE_KEY CLEVYLO_VERSION="$release_version" CLEVYLO_BUILD_NUMBER="$release_build_number" \
  "$workspace_dir/scripts/build.sh"

# Verify the actual archive outside file-provider-managed workspaces, where
# Finder metadata can otherwise invalidate a signature after it is verified.
release_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/clevylo-release.XXXXXX")"
trap 'rm -rf "$release_check_dir"' EXIT
release_archive="$release_check_dir/Clevylo.zip"
cp "$build_dir/Clevylo.zip" "$release_archive"
mkdir "$release_check_dir/extracted"
ditto -x -k "$release_archive" "$release_check_dir/extracted"
app_bundle="$release_check_dir/extracted/Clevylo.app"
app_binary="$app_bundle/Contents/MacOS/Clevylo"
if [[ ! -x "$app_binary" ]]; then
  printf 'Release archive does not contain the Clevylo app executable.\n' >&2
  exit 1
fi
codesign --verify --deep --strict --all-architectures "$app_bundle"

# Verify Sparkle's retained framework/helper signatures and both architectures.
# Its original helper entitlements are intentional; XCTest permissions are not.
sparkle_framework="$app_bundle/Contents/Frameworks/Sparkle.framework"
sparkle_version_dir="$sparkle_framework/Versions/B"
for helper_binary in "$sparkle_version_dir/Sparkle" "$sparkle_version_dir/Autoupdate" \
  "$sparkle_version_dir/Updater.app/Contents/MacOS/Updater" \
  "$sparkle_version_dir/XPCServices/Installer.xpc/Contents/MacOS/Installer" \
  "$sparkle_version_dir/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"; do
  for architecture in arm64 x86_64; do
    lipo "$helper_binary" -verify_arch "$architecture"
  done
  codesign --verify --strict --all-architectures "$helper_binary"
  codesign --display --entitlements :- "$helper_binary" \
    > "$release_check_dir/$(basename "$helper_binary")-entitlements.plist" 2>/dev/null
done

for architecture in arm64 x86_64; do
  lipo "$app_binary" -verify_arch "$architecture"
  codesign --display --arch "$architecture" --entitlements :- "$app_bundle" \
    > "$release_check_dir/entitlements-$architecture.plist" 2>/dev/null
  xcrun vtool -show-build -arch "$architecture" "$app_binary" \
    > "$release_check_dir/build-$architecture.txt"
done

python3 - "$app_bundle" "$release_version" "$release_build_number" "$release_check_dir" <<'PY'
import pathlib
import plistlib
import re
import sys

app = pathlib.Path(sys.argv[1])
expected_version, expected_build = sys.argv[2:4]
check_dir = pathlib.Path(sys.argv[4])
if {path.name for path in app.parent.iterdir()} != {"Clevylo.app"}:
    raise SystemExit("Release archive contains files outside Clevylo.app")
with (app / "Contents/Info.plist").open("rb") as handle:
    info = plistlib.load(handle)
if not (app / "Contents/Resources/Sparkle-LICENSE.txt").is_file():
    raise SystemExit("Release is missing Sparkle's third-party license notices")

expected = {
    "CFBundleIdentifier": "com.clevylo.app",
    "CFBundleExecutable": "Clevylo",
    "CFBundleShortVersionString": expected_version,
    "CFBundleVersion": expected_build,
    "LSMinimumSystemVersion": "14.0",
}
for key, value in expected.items():
    if info.get(key) != value:
        raise SystemExit(f"Release metadata mismatch: {key} is {info.get(key)!r}, expected {value!r}")

for path in app.rglob("*"):
    if path.suffix.lower() in {".xctest", ".dsym"} or path.name == "PlugIns":
        raise SystemExit(f"Release contains a test/debug bundle: {path.relative_to(app)}")

for path in check_dir.glob("*-entitlements.plist"):
    raw_entitlements = path.read_bytes().strip()
    entitlements = plistlib.loads(raw_entitlements) if raw_entitlements else {}
    if any(entitlements.get(key) for key in (
        "com.apple.security.get-task-allow",
        "com.apple.security.cs.disable-library-validation",
    )):
        raise SystemExit(f"Sparkle helper contains test/debug entitlements: {path.name}")

for architecture in ("arm64", "x86_64"):
    entitlement_bytes = (check_dir / f"entitlements-{architecture}.plist").read_bytes().strip()
    # The ad-hoc distributed app intentionally has no entitlements. In
    # particular, XCTest's get-task-allow and library-validation exceptions
    # must never escape from Debug into a downloadable release.
    if entitlement_bytes and plistlib.loads(entitlement_bytes):
        raise SystemExit(f"Release {architecture} slice contains unexpected entitlements")
    build_info = (check_dir / f"build-{architecture}.txt").read_text()
    if not re.search(r"^\s*platform MACOS\s*$", build_info, re.MULTILINE):
        raise SystemExit(f"Release {architecture} slice is not a macOS binary")
    if not re.search(r"^\s*minos 14\.0(?:\.0)?\s*$", build_info, re.MULTILINE):
        raise SystemExit(f"Release {architecture} slice does not target macOS 14.0")
PY

"$workspace_dir/scripts/generate-appcast.sh" "$release_version" "$release_build_number" \
  "$release_archive" "$app_bundle" "$release_check_dir/appcast.xml"

release_output_dir="$workspace_dir/build/release"
versioned_archive="Clevylo-$release_version-macOS-universal.zip"
stable_archive="Clevylo-macOS-universal.zip"
mkdir -p "$release_output_dir"
# Only the current version may match the publisher's versioned-archive glob.
# Preserve unrelated build files; replace earlier generated release archives.
for old_archive in "$release_output_dir"/Clevylo-[0-9]*-macOS-universal.zip; do
  if [[ -f "$old_archive" ]]; then rm -f -- "$old_archive"; fi
done
cp "$release_archive" "$release_output_dir/$versioned_archive"
cp "$release_archive" "$release_output_dir/$stable_archive"
cp "$release_check_dir/appcast.xml" "$release_output_dir/appcast.xml"
(
  cd "$release_output_dir"
  shasum -a 256 "$versioned_archive" "$stable_archive" appcast.xml > "$release_check_dir/SHA256SUMS"
)
mv "$release_check_dir/SHA256SUMS" "$release_output_dir/SHA256SUMS"
printf 'Verified release: %s (build %s)\n' "$release_version" "$release_build_number"
printf 'Assets: %s\n' "$release_output_dir/$versioned_archive" "$release_output_dir/$stable_archive" "$release_output_dir/appcast.xml" "$release_output_dir/SHA256SUMS"

#!/bin/bash
set -euo pipefail
workspace_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${CLEVYLO_BUILD_DIR:-$workspace_dir/build}"
if [[ "$build_dir" != /* ]]; then
  printf 'CLEVYLO_BUILD_DIR must be an absolute path.\n' >&2
  exit 2
fi
cd "$workspace_dir"
build_action=build
build_configuration=Release
case "${1:-}" in
  --for-testing) build_action=build-for-testing; build_configuration=Debug ;;
  '') ;;
  *) printf 'Usage: %s [--for-testing]\n' "$0" >&2; exit 2 ;;
esac
if [[ "$#" -gt 1 ]]; then printf 'Usage: %s [--for-testing]\n' "$0" >&2; exit 2; fi

# Release automation supplies the version at build time, before signing. These
# overrides keep the checked-in project and its XcodeGen source in sync.
build_settings=(CODE_SIGNING_ALLOWED=NO)
if [[ -n "${CLEVYLO_VERSION:-}" || -n "${CLEVYLO_BUILD_NUMBER:-}" ]]; then
  if [[ ! "${CLEVYLO_VERSION:-}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    printf 'CLEVYLO_VERSION must be a stable semantic version, such as 1.2.3.\n' >&2
    exit 2
  fi
  if [[ ! "${CLEVYLO_BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]]; then
    printf 'CLEVYLO_BUILD_NUMBER must be a positive integer.\n' >&2
    exit 2
  fi
  build_settings+=("MARKETING_VERSION=$CLEVYLO_VERSION" "CURRENT_PROJECT_VERSION=$CLEVYLO_BUILD_NUMBER")
fi
if [[ "$build_configuration" == Release ]]; then
  build_settings+=("ARCHS=arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
fi
xcodebuild -project Clevylo.xcodeproj -scheme Clevylo -configuration "$build_configuration" \
  -destination 'platform=macOS' -derivedDataPath "$build_dir" \
  "${build_settings[@]}" "$build_action"
# File-provider-managed workspaces can reattach Finder metadata during the build.
# Clear only generated bundles immediately before each local ad-hoc signature.
while IFS= read -r -d '' bundle_path; do
  # Preserve Sparkle's signed helpers. Re-sign only the outer framework because
  # Xcode strips its headers/modules when embedding it, invalidating its seal.
  # --deep would incorrectly give the helpers XCTest entitlements in Debug.
  if [[ "$bundle_path" == */Sparkle.framework/* ]]; then continue; fi
  signing_options=(--force --sign -)
  if [[ "$build_configuration" == Debug && "$bundle_path" != *.framework ]]; then
    signing_options+=(--entitlements "$workspace_dir/scripts/local-test.entitlements")
  fi
  # The file provider can race the first metadata clear. Retry only this known
  # generated-bundle metadata error; propagate every other signing failure.
  signing_log="$(mktemp "$build_dir/signing.XXXXXX")"
  signed=false
  for signing_attempt in 1 2 3; do
    xattr -cr "$bundle_path"
    if codesign "${signing_options[@]}" "$bundle_path" >"$signing_log" 2>&1; then
      signed=true
      break
    fi
    if ! /usr/bin/grep -q 'resource fork, Finder information, or similar detritus' "$signing_log"; then break; fi
  done
  cat "$signing_log"
  rm -f "$signing_log"
  if [[ "$signed" != true ]]; then exit 1; fi
done < <(find "$build_dir/Build/Products/$build_configuration" -depth \( -name '*.app' -o -name '*.xctest' -o -name '*.framework' \) -type d -print0)
app_bundle="$build_dir/Build/Products/$build_configuration/Clevylo.app"
xattr -cr "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
if [[ "$build_configuration" == Release ]]; then
  # Preserve a clean deliverable even if the workspace's file provider later
  # attaches Finder metadata to the expanded .app again.
  ditto -c -k --norsrc --noextattr --noqtn --keepParent "$app_bundle" "$build_dir/Clevylo.zip"
  printf 'Archive: %s\n' "$build_dir/Clevylo.zip"
fi
printf 'Built: %s\n' "$build_dir/Build/Products/$build_configuration/Clevylo.app"

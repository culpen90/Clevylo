#!/bin/bash
set -euo pipefail
workspace_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$workspace_dir"
build_action=build
build_configuration=Release
if [[ "${1:-}" == "--for-testing" ]]; then build_action=build-for-testing; build_configuration=Debug; fi
xcodebuild -project Clevylo.xcodeproj -scheme Clevylo -configuration "$build_configuration" \
  -destination 'platform=macOS' -derivedDataPath "$workspace_dir/build" \
  CODE_SIGNING_ALLOWED=NO "$build_action"
# File-provider-managed workspaces can reattach Finder metadata during the build.
# Clear only generated bundles immediately before each local ad-hoc signature.
while IFS= read -r -d '' bundle_path; do
  signing_options=(--force --deep --sign -)
  if [[ "$build_configuration" == Debug ]]; then
    signing_options+=(--entitlements "$workspace_dir/scripts/local-test.entitlements")
  fi
  # The file provider can race the first metadata clear. Retry only this known
  # generated-bundle metadata error; propagate every other signing failure.
  signing_log="$(mktemp "$workspace_dir/build/signing.XXXXXX")"
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
done < <(find "$workspace_dir/build/Build/Products/$build_configuration" -depth \( -name '*.app' -o -name '*.xctest' \) -type d -print0)
app_bundle="$workspace_dir/build/Build/Products/$build_configuration/Clevylo.app"
xattr -cr "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
if [[ "$build_configuration" == Release ]]; then
  # Preserve a clean deliverable even if the workspace's file provider later
  # attaches Finder metadata to the expanded .app again.
  ditto -c -k --norsrc --noextattr --noqtn --keepParent "$app_bundle" "$workspace_dir/build/Clevylo.zip"
  printf 'Archive: %s\n' "$workspace_dir/build/Clevylo.zip"
fi
printf 'Built: %s\n' "$workspace_dir/build/Build/Products/$build_configuration/Clevylo.app"

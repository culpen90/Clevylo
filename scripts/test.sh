#!/bin/bash
set -euo pipefail
workspace_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${CLEVYLO_BUILD_DIR:-$workspace_dir/build}"
if [[ "$build_dir" != /* ]]; then
  printf 'CLEVYLO_BUILD_DIR must be an absolute path.\n' >&2
  exit 2
fi
cd "$workspace_dir"
"$workspace_dir/scripts/build.sh" --for-testing
test_arguments=(-project Clevylo.xcodeproj -scheme Clevylo -configuration Debug
  -destination 'platform=macOS' -derivedDataPath "$build_dir" CODE_SIGNING_ALLOWED=NO)
case "${1:-}" in
  --unit) test_arguments+=(-only-testing:ClevyloTests) ;;
  --ui) test_arguments+=(-only-testing:ClevyloUITests) ;;
  '') ;;
  *) printf 'Usage: %s [--unit|--ui]\n' "$0" >&2; exit 2 ;;
esac
xcodebuild "${test_arguments[@]}" test-without-building

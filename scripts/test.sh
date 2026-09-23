#!/bin/bash
set -euo pipefail
workspace_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$workspace_dir"
"$workspace_dir/scripts/build.sh" --for-testing
test_arguments=(-project Clevylo.xcodeproj -scheme Clevylo -configuration Debug
  -destination 'platform=macOS' -derivedDataPath "$workspace_dir/build" CODE_SIGNING_ALLOWED=NO)
case "${1:-}" in
  --unit) test_arguments+=(-only-testing:ClevyloTests) ;;
  --ui) test_arguments+=(-only-testing:ClevyloUITests) ;;
  '') ;;
  *) printf 'Usage: %s [--unit|--ui]\n' "$0" >&2; exit 2 ;;
esac
xcodebuild "${test_arguments[@]}" test-without-building

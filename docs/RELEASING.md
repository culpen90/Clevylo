# Release packaging

The first release is **1.0.0 (build 1)**, distributed as `Clevylo-1.0.0-macOS-universal.zip` with `SHA256SUMS`. The archive contains `Clevylo.app`; source code is available separately through GitHub. It requires macOS 14 or later and includes arm64 and x86_64 binaries.

## Signing and installation

This release is ad-hoc signed. It is **not Developer ID signed or notarized**, and passing local signature verification does not establish Gatekeeper approval. Users may need to permit this specific app through **System Settings → Privacy & Security → Open Anyway** after the first attempted launch. Follow [Apple's current guidance](https://support.apple.com/en-us/102445); managed computers may not allow an exception. No system-wide security changes are required by Clevylo.

Expand the ZIP, move the app to Applications, and open it. Updates are installed manually. The library remains in `~/Library/Application Support/Clevylo/`, outside the app bundle. Quit Clevylo before replacing an installed copy.

## Reproducing the archive

Use the checked-in Xcode project on a Mac with Xcode. The version is recorded in both `project.yml` and `Clevylo.xcodeproj/project.pbxproj`.

```sh
./scripts/test.sh
./scripts/build.sh
mkdir -p build/release
cp build/Clevylo.zip build/release/Clevylo-1.0.0-macOS-universal.zip
(cd build/release && shasum -a 256 Clevylo-1.0.0-macOS-universal.zip > SHA256SUMS)
```

The build script strips extended attributes only from generated bundles, signs the Release app without debug/test entitlements, verifies its signature, and archives without Finder metadata. Check the extracted archive in a clean temporary directory because file providers can reattach metadata to expanded bundles in Documents:

```sh
release_check_dir="$(mktemp -d /tmp/clevylo-release-check.XXXXXX)"
ditto -x -k build/release/Clevylo-1.0.0-macOS-universal.zip "$release_check_dir"
codesign --verify --deep --strict "$release_check_dir/Clevylo.app"
lipo "$release_check_dir/Clevylo.app/Contents/MacOS/Clevylo" -verify_arch arm64
lipo "$release_check_dir/Clevylo.app/Contents/MacOS/Clevylo" -verify_arch x86_64
plutil -p "$release_check_dir/Clevylo.app/Contents/Info.plist"
```

Before publication, confirm the bundle version, macOS minimum, system-only linked libraries, absence of test bundles and private data, and a real launch from the extracted app. Tag the exact source commit used for the build. Upload the ZIP and checksum file to that tag's GitHub release, then download the public assets again and verify their SHA-256 and extracted signature. The checksum verifies file integrity; it is not an independent developer signature.

## Verification limits

The existing source passed 63 unit tests and one native UI smoke test on Apple Silicon with macOS 26.6.2 and Xcode 27.0. See [the detailed verification record](VERIFICATION.md). Packaging a universal binary does not prove execution on Intel hardware or macOS 14. Live model inference requires a compatible installed Ollama model or the user's OpenRouter key and remains a separate check. No model, credential, or student library is included in the release.

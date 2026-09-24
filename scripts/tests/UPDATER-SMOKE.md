# Native updater integration smoke test

Build the real universal Release app first with `./scripts/build.sh`, then prepare
isolated copies. This command does not build, launch an app, or start a server:

```sh
python3 scripts/tests/prepare-update-fixture.py
```

If building outside the checkout, pass the same `CLEVYLO_BUILD_DIR` environment
variable. `--archive /absolute/path/Clevylo.zip` can select a different Release ZIP.

The output records the generated `/private/tmp/clevylo-updater-smoke-*` directory.
Its `REPRO.txt` contains exact commands to serve **only its feed directory** on
127.0.0.1 and launch the old app. Use `--port 8765` if a fixed port is needed; the
default selects a currently unused port, which must still be free when serving.

Both app copies use a unique bundle ID, updater defaults domain, display name,
and isolated library. The fixture changes only copies extracted from
`build/Clevylo.zip`: versions 0.0.1/build 1 and 0.0.2/build 2, loopback feed, and a
fresh throwaway Ed25519 key. It checks that Sparkle's nested framework and helper
bytes remain unchanged and verifies their signatures. Only the outer app gets
an ad-hoc signature, without test entitlements. Production signing keys and
Keychain accounts are not read. The fixture keys are outside the served folder.

Launch the app with the exact `open -n` command in `REPRO.txt`. Avoid invoking the
executable directly unless `CLEVYLO_DATA_DIR` is also explicitly supplied. Both
copies include `LSEnvironment.CLEVYLO_DATA_DIR`, because the pinned Sparkle 2.10.0 relaunches
with `NSWorkspace.openURL` and does not preserve initial `--data-dir` arguments.
[Apple documents](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html)
that Launch Services sets `LSEnvironment` variables when opening the app. Verify
the library path on both the initial launch and the relaunch before counting the
smoke test as passed.

1. In the temporary app, create a subject and a note containing synthetic text.
   Confirm `library/library.json` exists under the fixture directory and contains
   that text. No provider setup is needed.
2. Choose **Check for Updates…** from the app menu. Confirm the 0.0.2 update and
   its local release notes, then choose **Install Update**.
3. Choose **Install and Relaunch**. Confirm the original process exits and the
   app restarts from the same `installed/` path.
4. Check the installed copy's `Contents/Info.plist`: the version must be 0.0.2
   and build 2. Verify its code signature again with
   `codesign --verify --deep --strict --all-architectures <app-path>`.
5. Verify that the synthetic note is still visible and remains in the fixture's
   `library/library.json`. Confirm the relaunched process still has the fixture
   `CLEVYLO_DATA_DIR` environment value, using `ps eww -p <pid>` or an equivalent
   process inspection restricted to that fixture process.
6. Choose **Check for Updates…** again and confirm the up-to-date dialog. Keep
   native screenshots and the loopback request log with the test evidence.
7. Quit the temporary app, then stop the loopback server. All app copies, library
   data, and keys are under the generated directory. macOS may also create
   preferences/caches for the unique IDs recorded in `manifest.json`; remove only
   those fixture-specific entries if cleaning up.

The fixture proves installation and relaunch using the production app binary and
Sparkle framework. It does not establish Gatekeeper behavior for downloaded
public releases, Developer ID/notarization, or access to the public GitHub feed.

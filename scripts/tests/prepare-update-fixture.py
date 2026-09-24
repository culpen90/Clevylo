#!/usr/bin/env python3
"""Prepare a local, isolated old-to-new Sparkle fixture; never launch or serve it.

Uses the actual Release ZIP. Only temporary copies get new bundle metadata and
an outer ad-hoc signature. Sparkle's signed binaries are kept byte-for-byte.
The fixture uses a new throwaway signing key, never Keychain or a release key.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shlex
import socket
import subprocess
import tempfile
import uuid


WORKSPACE = Path(__file__).resolve().parents[2]
BUILD_DIR = Path(os.environ.get("CLEVYLO_BUILD_DIR", str(WORKSPACE / "build")))
SPARKLE_BIN = BUILD_DIR / "SourcePackages/artifacts/sparkle/Sparkle/bin"


def run(*arguments: object) -> str:
    environment = os.environ.copy()
    # Explicit --ed-key-file is used below. Keep unrelated release credentials
    # out of child processes as well, even when this is run in a release shell.
    environment.pop("SPARKLE_PRIVATE_KEY", None)
    environment.pop("SPARKLE_KEYCHAIN_ACCOUNT", None)
    result = subprocess.run(
        [str(value) for value in arguments],
        env=environment,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout


def framework_digest(framework: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(framework.rglob("*")):
        digest.update(str(path.relative_to(framework)).encode())
        if path.is_symlink():
            digest.update(b"symlink\0" + os.readlink(path).encode())
        elif path.is_file():
            digest.update(path.read_bytes())
    return digest.hexdigest()


def verify_app(app: Path) -> None:
    run("codesign", "--verify", "--deep", "--strict", "--all-architectures", app)
    for architecture in ("arm64", "x86_64"):
        entitlements = run("codesign", "--display", "--arch", architecture, "--entitlements", ":-", app).strip()
        if entitlements and plistlib.loads(entitlements.encode()):
            raise RuntimeError("Fixture requires a Release app with no outer app entitlements")
    if (app / "Contents/PlugIns").exists():
        raise RuntimeError("Fixture requires a Release app without test bundles")


def unused_port() -> int:
    # This only selects an available port; the fixture does not start a server.
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, default=BUILD_DIR / "Clevylo.zip")
    parser.add_argument("--port", type=int, default=None, help="Loopback port to use later (default: currently unused port)")
    arguments = parser.parse_args()
    archive = arguments.archive.resolve()
    if not archive.is_file():
        parser.error(f"Release archive does not exist: {archive}; run ./scripts/build.sh first")
    if not (SPARKLE_BIN / "generate_appcast").is_file():
        parser.error("Pinned Sparkle tools are missing; resolve them with ./scripts/build.sh first")
    port = arguments.port if arguments.port is not None else unused_port()
    if not 1024 <= port <= 65535:
        parser.error("--port must be between 1024 and 65535")

    fixture = Path(tempfile.mkdtemp(prefix="clevylo-updater-smoke-", dir="/tmp")).resolve()
    fixture.chmod(0o700)
    identity = uuid.uuid4().hex
    bundle_id = f"com.clevylo.updater-smoke.{identity}"
    display_name = f"Clevylo Updater Smoke {identity[:8]}"
    app_name = display_name + ".app"
    base_url = f"http://127.0.0.1:{port}/"
    for directory in ("source", "installed", "next", "feed", "keys", "library"):
        (fixture / directory).mkdir(mode=0o700)

    run("ditto", "-x", "-k", archive, fixture / "source")
    source_app = fixture / "source/Clevylo.app"
    if not (source_app / "Contents/MacOS/Clevylo").is_file():
        raise RuntimeError(f"Release archive is missing Clevylo.app; fixture: {fixture}")
    verify_app(source_app)
    original_framework_digest = framework_digest(source_app / "Contents/Frameworks/Sparkle.framework")

    # Sparkle 2's --ed-key-file accepts a base64-encoded 32-byte Ed25519 seed.
    # CryptoKit's raw private representation is that seed; no Keychain is used.
    key_script = fixture / "keys/generate.swift"
    key_script.write_text("""import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
try key.publicKey.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
""")
    private_key = fixture / "keys/private-key"
    public_key_file = fixture / "keys/public-key"
    run("xcrun", "swift", key_script, private_key, public_key_file)
    private_key.chmod(0o600)
    public_key = public_key_file.read_text().strip()

    def make_app(destination: Path, version: str, build: str) -> None:
        run("ditto", "--noextattr", "--noqtn", source_app, destination)
        plist_path = destination / "Contents/Info.plist"
        with plist_path.open("rb") as handle:
            info = plistlib.load(handle)
        info.update({
            "CFBundleIdentifier": bundle_id,
            "CFBundleName": display_name,
            "CFBundleDisplayName": display_name,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
            "SUDefaultsDomain": bundle_id + ".updates",
            "SUFeedURL": base_url + "appcast.xml",
            "SUPublicEDKey": public_key,
            "SUEnableAutomaticChecks": False,
            "SUAllowsAutomaticUpdates": False,
            "SUAutomaticallyUpdate": False,
            "SUEnableSystemProfiling": False,
            # Sparkle relaunches through NSWorkspace.openURL. Launch Services
            # reapplies this variable, unlike the original --data-dir argument.
            "LSEnvironment": {"CLEVYLO_DATA_DIR": str(fixture / "library")},
        })
        info.setdefault("NSAppTransportSecurity", {}).setdefault("NSExceptionDomains", {})["127.0.0.1"] = {
            "NSExceptionAllowsInsecureHTTPLoads": True,
        }
        with plist_path.open("wb") as handle:
            plistlib.dump(info, handle)
        # Deliberately omit --deep: retain Sparkle's official nested signatures.
        run("xattr", "-cr", destination)
        run("codesign", "--force", "--sign", "-", destination)
        verify_app(destination)
        if framework_digest(destination / "Contents/Frameworks/Sparkle.framework") != original_framework_digest:
            raise RuntimeError("Sparkle framework changed while preparing fixture")

    installed_app = fixture / "installed" / app_name
    next_app = fixture / "next" / app_name
    make_app(installed_app, "0.0.1", "1")
    make_app(next_app, "0.0.2", "2")
    update_archive = fixture / "feed/Clevylo-Smoke-0.0.2.zip"
    run("ditto", "-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--keepParent", next_app, update_archive)
    (fixture / "feed/Clevylo-Smoke-0.0.2.html").write_text(
        "<h2>Local update smoke test</h2><p>This temporary version verifies signed download, installation, restart, and library preservation.</p>"
    )
    run(SPARKLE_BIN / "generate_appcast", "--ed-key-file", private_key,
        "--maximum-deltas", "0", "--download-url-prefix", base_url,
        "--embed-release-notes", "-o", fixture / "feed/appcast.xml", fixture / "feed")
    run(SPARKLE_BIN / "sign_update", "--ed-key-file", private_key, "--verify", fixture / "feed/appcast.xml")

    manifest = {
        "fixture": str(fixture),
        "installedApp": str(installed_app),
        "updatedAppSource": str(next_app),
        "bundleIdentifier": bundle_id,
        "displayName": display_name,
        "updaterDefaultsDomain": bundle_id + ".updates",
        "library": str(fixture / "library"),
        "feedDirectory": str(fixture / "feed"),
        "feedURL": base_url + "appcast.xml",
        "port": port,
        "expectedVersion": "0.0.2",
        "expectedBuild": "2",
        "releaseArchiveSHA256": hashlib.sha256(archive.read_bytes()).hexdigest(),
        "sparkleFrameworkSHA256": original_framework_digest,
    }
    (fixture / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    serve = shlex.join(["python3", "-m", "http.server", str(port), "--bind", "127.0.0.1", "--directory", str(fixture / "feed")])
    launch = shlex.join(["open", "-n", str(installed_app)])
    (fixture / "REPRO.txt").write_text(
        "Start the loopback-only server (in its own terminal):\n" + serve + "\n\n"
        "Launch the installed old version through Launch Services:\n" + launch + "\n\n"
        "Do not launch source/ or next/. They are fixture inputs.\n"
        "1. Create a subject and note with synthetic text; confirm library/library.json contains them.\n"
        "2. Choose the app menu > Check for Updates. Confirm version 0.0.2, then choose Install Update.\n"
        "3. After download, choose Install and Relaunch. Confirm the old process exits and the same installed app relaunches.\n"
        "4. Confirm installed app Info.plist says version 0.0.2/build 2, and the synthetic note remains visible.\n"
        "5. Confirm the new process uses the fixture library (ps eww or open file inspection), and library.json retains the note.\n"
        "6. Check for updates again; confirm the up-to-date dialog. Quit this fixture app and stop the server.\n\n"
        "No app was launched and no server was started by fixture preparation.\n"
        "All app copies, the synthetic library, and throwaway signing files are under this fixture directory.\n"
        "macOS may additionally create defaults/caches for the unique IDs recorded in manifest.json.\n"
        "The release key and release Keychain account are never used. The feed directory contains no signing key.\n"
        "Provider credentials are not needed; do not set up an AI provider or use provider actions.\n"
    )
    print(json.dumps(manifest, indent=2))
    print("\nPrepared only; repro commands are in " + str(fixture / "REPRO.txt"))


if __name__ == "__main__":
    main()

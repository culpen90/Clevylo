# Clevylo

**Make it click.** A native macOS study workspace built with SwiftUI and AppKit.

Keep subjects, documents, notes, assignments, conversations, flashcards, and practice quizzes together. Clevylo uses **Ollama locally** or **OpenRouter in the cloud**. There is no account system, telemetry, or hosted backend.

## Download and install

Download **[the latest Clevylo for macOS](https://github.com/culpen90/Clevylo/releases/latest/download/Clevylo-macOS-universal.zip)** or browse the [release notes and checksums](https://github.com/culpen90/Clevylo/releases/latest). Requires macOS 14 or later; the app includes Apple Silicon and Intel binaries. Xcode is not needed to run the download.

1. Expand the ZIP and move **Clevylo.app** to **Applications**.
2. Open Clevylo. This release is **ad-hoc signed, not Developer ID signed or notarized**, so macOS may block the first launch.
3. If you trust this download, follow [Apple's instructions](https://support.apple.com/en-us/102445): after attempting to open it, use **System Settings → Privacy & Security → Open Anyway**, then confirm. Managed Macs may prohibit this exception.

Local organization and study work without provider setup. AI features require your own running Ollama model or OpenRouter key; neither is bundled. See [release verification and packaging](docs/RELEASING.md).

### Update from the app

Choose **Clevylo → Check for Updates…** to see whether a newer version is available, read its release notes, and download and install it. Clevylo saves your library before restarting to finish an update. Your library and preferences stay on this Mac.

In **Clevylo → Settings → Updates**, you can enable automatic update checks, see the installed version and last check time, or check immediately. Clevylo asks whether you want automatic checks after its first launch; downloads and installation always require your choice. Update requests contact GitHub and do not include your library, documents, conversations, API key, analytics, or system profile. Update archives are verified with a release signature before installation.

If you are running an older Clevylo version without **Check for Updates…**, install the latest download once to get in-app updates.

## Build and run

Requires macOS 14 or later and a stable Xcode with the macOS SDK. The checked-in Xcode project includes the shared **Clevylo** scheme. Xcode resolves the pinned [Sparkle](https://sparkle-project.org/) package for native app updates during the first build.

```sh
./scripts/build.sh
open build/Build/Products/Release/Clevylo.app
```

The script also creates `build/Clevylo.zip`, a clean archive of the universal Apple Silicon/Intel app without Finder metadata. Extract it before launching.

Alternatively, open `Clevylo.xcodeproj`, select **Clevylo → My Mac**, and Run. The script is the reproducible route for file-provider-managed workspaces: it clears Finder metadata only from generated bundles immediately before local ad-hoc signing. It does not alter system settings or source-file attributes.

`project.yml` is the XcodeGen source. If changing target configuration, regenerate with `xcodegen generate`. XcodeGen is not needed to build the checked-in project.

The deployment target is macOS 14 for the native SwiftUI navigation and observation APIs used here. Validation was performed on the available Apple Silicon Mac with Xcode 27.0, using APIs available on macOS 14. Compatibility on an actual macOS 14 machine and Intel hardware has not been exercised.

## First use

1. Create a subject. Import PDFs, text, Markdown, or common images using **Import** or drag and drop.
2. Open a material to view it beside Tutor. **Extracted Text** lets you inspect and correct transcription, especially formulas. OCR and unreadable pages are explicitly flagged.
3. Write notes with autosave, and add assignments with local calendar deadlines and attached materials.
4. Set up AI using **Clevylo → Settings → AI Provider**. Choose sources before sending. General questions need no source.
5. Create a flashcard deck or quiz manually, or generate one from a topic and chosen materials. Edit the result before relying on its answer key.

Samples in `Samples/` are original synthetic teaching materials and are never automatically imported into your library.

Keyboard shortcuts: **⌘⇧N** new subject, **⌘N** new note, **⌘⇧I** import in a subject, **⌘1–4** navigation, and **⌘,** Settings. In flashcard review, **Return** reveals the answer, **1–4** rate recall, and **Escape** closes the session.

### Ollama

Install and run [Ollama](https://docs.ollama.com/quickstart), and install a suitable local model yourself. Clevylo connects only to `127.0.0.1:11434`, lists installed models, and never downloads a model. In Settings, click **Find Installed Models**, choose a tag, and **Test Connection**. Cloud-backed Ollama models are rejected. The local daemon is under your control.

### OpenRouter

Create an [OpenRouter API key](https://openrouter.ai/settings/keys), enter it in Settings, and click **Save Key**. It is stored in macOS Keychain. Discover models or enter an exact OpenRouter model ID. Enable cloud sharing after reading the disclosure, then test the connection. Applicable OpenRouter billing or credits are separate from a ChatGPT subscription.

Choose a model with structured-output support for generated study sets and image-input support for worksheets. Provider/model errors are surfaced; unavailable AI never produces a simulated answer. See [provider details and official API references](docs/PROVIDERS.md).

## Local storage and privacy

The default library is `~/Library/Application Support/Clevylo/`:

- `library.json`: relationships, extracted pages, notes, assignments, conversations, and study history.
- `Materials/`: UUID-named managed copies, independent of original filenames and locations.
- `settings.json`: provider, model, and consent preferences. **No API key.**

The OpenRouter credential is a device-local Keychain item under `com.clevylo.app.credentials`. No credentials or document contents are logged. Use Settings to remove the key. To back up your work, quit Clevylo and copy the entire library folder. Corrupt or unsupported snapshots are preserved and opened in a blocked state rather than overwritten.

AI requests include the current question, recent messages in that conversation, selected source excerpts, and explicitly attached images. Removing sources changes subsequent retrieval; earlier conversation text still forms part of that conversation, so start a new conversation to clear that context. Nothing uploads automatically. Model output cannot execute code, tools, or commands. Source links resolve only to actual retrieved passages and become unavailable when the corresponding text changes or is deleted. Citations indicate provenance, not a guarantee that a model interpreted the passage correctly.

For an isolated library:

```sh
open build/Build/Products/Release/Clevylo.app --args --data-dir "$PWD/build/MyTestLibrary"
```

Quit an existing instance first. `CLEVYLO_DATA_DIR` is also supported for automated test hosts. macOS may request access when a custom library is inside a protected folder such as Documents; the default Application Support library does not require that folder access.

## Testing

```sh
./scripts/test.sh --unit   # persistence, ingestion/OCR, retrieval, providers, study logic
./scripts/test.sh --ui     # isolated real macOS interface and restart smoke test
./scripts/test.sh          # both suites; requires an active macOS GUI session
```

**Verified on 2026-09-23:** the combined suite passed 63 unit tests and 1 native UI smoke test. The Release build and manual native interface checks also passed; live model inference still requires your setup.

Tests use synthetic fixtures and isolated data directories. Provider tests use deterministic URLProtocol responses, including cancellation of real URLSession tasks. Production always calls the selected real provider. UI tests require macOS permission to automate the interface; results and screenshots are saved under `build/Logs/Test/`. See [verification evidence](docs/VERIFICATION.md) for actual results and remaining environment checks.

### Automatic releases

GitHub Actions tests every pull request and push to `main`. After passing checks, changes on `main` automatically receive a version, Git tag, release notes, universal macOS ZIP, and SHA-256 checksums. Use Conventional Commit messages (or the PR title when squash merging): `fix:` / `perf:` for patches, `feat:` for minor releases, and `!` or a `BREAKING CHANGE:` footer for major releases. Documentation and maintenance commits alone do not create releases. See [release rules, previews, and recovery](docs/RELEASING.md).

### Review scheduling

Scheduling uses local calendar days, with a maximum interval of 365 days:

| Rating | Next interval |
| --- | --- |
| Again | Today, interval reset to 0 |
| Hard | At least 1 day, otherwise ceil(previous × 1.2) |
| Good | Initially 1 day, otherwise previous × 2 |
| Easy | Initially 3 days, otherwise previous × 3 |

Every rating records an actual review. Multiple-choice practice uses the saved answer key. Short answers are explicitly self-assessed against a sample answer, with optional AI feedback clearly labeled as suggestions rather than grades. No mastery percentages, streaks, or unseen activity are invented.

## Current boundaries

- Text extraction supports embedded PDF text first, then on-device Vision OCR for image-only pages/images. Imports are bounded at 50 MB, 200 PDF pages, and two million extracted characters. OCR can misread mathematical notation; inspect and correct it before use.
- Retrieval is local lexical passage ranking, not a semantic embedding database. It returns bounded excerpts only from selected sources.
- Native text renders Markdown emphasis/links, code blocks, and common Unicode mathematical notation. Complex LaTeX remains readable source notation; this version does not contain a full equation-typesetting engine.
- Image attachments to a tutor request are transient; imported material copies and conversation text persist. Reattach an image if you need it in a later request.
- Downloadable builds are **ad-hoc signed and not notarized**. Expect a macOS first-launch security prompt; see the installation instructions above. The release app has no debug/test entitlements; test builds have the entitlements needed by XCTest. Sparkle provides in-app updates; there is no App Store distribution.
- Live model inference requires a running installed Ollama model or an OpenRouter key. Neither is supplied with the app.

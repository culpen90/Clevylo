# Verification record

This record separates isolated adapter checks from integrated application testing and live model inference. All test content is synthetic. No model downloads, paid requests, real API-key writes, or private study materials were used in the checks below.

## Isolated provider checks - completed

On 2026-09-23, a focused XCTest bundle compiled from the production models, AI provider, Keychain wrapper, and `ProviderTests.swift` ran **17 tests with 0 failures**. The temporary harness resides in ignored `.verification` build output; the same test source belongs to the main Xcode test target.

Covered behavior:

- OpenRouter SSE and Ollama NDJSON through URLSession with synthetic URLProtocol responses.
- Arbitrary byte boundaries, Unicode, multiline SSE events, comments, repeated finish frames, malformed events, missing terminal events, output truncation, refusal, and whitespace-only answers.
- Cancellation while awaiting output and after the first text delta; both checks observed the underlying network operation stop.
- HTTP 400, 401, 402, 403, 404, 429, and 503; timeout and offline mapping; sensitive HTTP and streaming error bodies are not exposed in the displayed message.
- Request-scoped reference data separate from trusted instructions; image encoding; provider-specific JSON-schema fields; no tool definitions; role validation.
- OpenRouter authorization isolated from Ollama and public catalog requests; cloud Ollama aliases blocked before student content is sent; redirects rejected.

These are client-contract tests, not proof of remote model quality, paid-account readiness, upstream policy, or actual model capability. Keychain permission prompts and a real credential round trip were not exercised by this isolated suite.

## Read-only endpoint checks - completed

- `http://127.0.0.1:11434/api/tags` refused the connection. No running Ollama service was available at the configured endpoint during the probe.
- `https://openrouter.ai/api/v1/models` returned HTTP 200 with 456 catalog entries. This public catalog request contained no API key or study content.

The catalog result demonstrates discovery availability at that moment. It does not demonstrate successful authenticated generation.

## App Transport Security probe - completed

A separate tiny app bundle used URLSession against a temporary synthetic loopback HTTP listener on an ephemeral port. It returned HTTP 200 both without an ATS exception and with an explicit exception for `127.0.0.1` on this development host. The listener was shut down after the test and did not occupy Ollama's port.

Current Apple guidance supports specific IP exceptions on macOS 14 and later. The app uses a narrowly scoped loopback HTTP exception. URLProtocol fixtures bypass ATS and cannot establish deployed ATS behavior. See [Apple NSExceptionDomains documentation](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSAppTransportSecurity/NSExceptionDomains) and [local networking documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).

## Original sample materials - completed

`swift scripts/make-samples.swift` creates `Samples/Biology.md`, `Samples/Algebra.txt`, `Samples/Worksheet.png`, and `Samples/StudySample.pdf` using macOS AppKit, Core Graphics, and PDFKit. The PDF has two US Letter pages: embedded selectable biology text on page 1 and a raster algebra worksheet on page 2 for OCR practice.

PDFKit checks passed: exactly two pages, expected selectable text on page 1, and no embedded text on page 2. Both final PDF pages were rendered with Poppler and visually inspected; text, margins, table, grid, and footer are readable with no clipping or overlap. The standalone worksheet is 1,224 x 1,584 pixels. Samples contain original educational prose and simple problems, with no personal information.

## Integrated build and application checks

Environment: Apple Silicon, macOS 26.6.2 (25G83), Xcode 27.0 (27A266a), macOS SDK 27. Deployment target is macOS 14. No model or toolchain downloads were performed.

`./scripts/test.sh` completed against the final source on 2026-09-23 at 16:01 EDT: **64 tests, 0 failures — 63 unit tests and 1 native UI smoke test**. The unit suite includes 17 ingestion/retrieval tests, 17 persistence/date/navigation tests, 17 provider tests, 10 study/parser/scheduling tests, and 2 privacy tests. The Keychain test saves, replaces, reads, and deletes a synthetic value under a unique test service; it does not touch the production credential item. Link handling rejects executable and local URL schemes.

Combined result bundle: `build/Logs/Test/Test-Clevylo-2026.09.23_15-58-33--0400.xcresult`.

The integrated persistence test imports into two subjects, saves notes/assignments/conversations/study history, reloads the complete library, and checks managed files and source isolation. Failure tests cover corrupt snapshots, unsafe filenames, failed save rollback, failed imports, changed/deleted references, and interrupted conversations.

The end-to-end test uses a fresh unique `build/UI-smoke` library. It creates two subjects, distinct notes and assignments, completes only one assignment, edits a manual deck, records a Good review through native keyboard controls, restarts, and checks both the rendered workspace and persisted relationships, review history, interval, and next local calendar day. The result contains a retained screenshot.


The UI runner initially stalled on accessibility label reads and later timed out enabling automation mode. The test now uses native keyboard review and checks the actual saved review data; restarting the stuck test process restored automation. The final run above passed. Xcode also emits unrelated CoreDevice/CoreSimulator version warnings on this machine; macOS builds and tests completed despite those warnings.

`./scripts/build.sh` produced a **Release universal app (arm64 and x86_64)** and `build/Clevylo.zip`. Local ad-hoc signature verification passed during packaging; Release has no XCTest plug-in or debug/test entitlements. The ZIP omits extended attributes because this workspace's file provider can reattach Finder metadata to an expanded bundle after signing. The archive is the preferred portable local artifact. Intel execution and an actual macOS 14 host remain untested.

## Manual native interface checks - completed

All work used isolated synthetic libraries in `build/ManualSmoke` and `build/SourceSmoke`, plus fresh test libraries. The app's appearance was restored to System afterward.

- Onboarding and genuine empty states; native subject/note/navigation/import/settings shortcuts; accessible control labels inspected through the native accessibility tree.
- Native file picker imports of the two-page PDF into Biology and plain text into Algebra. Both managed copies opened, with subject isolation. PDF page 1 used embedded text and page 2 used OCR; the OCR warning, page navigation, extraction correction, and document/Tutor split were exercised. Corrected text survived restart.
- Assignment creation with instructions and attached Algebra material; deadline changed from October 2 to October 5, completion saved, and Today remained correct after restart. Persisted data confirmed the deadline, attachment, and completion.
- Manual quiz creation, answer comparison, explicit short-answer self-assessment, finish, restart, and one actual recorded answer. The automated smoke separately exercises flashcard review.
- Public OpenRouter catalog discovery returned 456 models in the actual Settings UI. Ollama discovery showed an actionable unavailable-daemon error. Missing-model sending showed a setup error and no simulated answer.
- A clearly labeled synthetic saved conversation, created with production ingestion and source-index code, exercised PDF citation excerpt/open-to-page, note citation/open-editor, and Save response as note. No model was called for this fixture. The newly saved note appeared in the subject's notes.
- Light and dark appearances and resizing from the default window to approximately 908 × 632 points. A clipped study layout found during this pass was fixed, rebuilt, and visually rechecked in both appearances. No custom animations are added; native system controls govern reduced-motion behavior. Spoken VoiceOver and a changed system reduced-motion setting were not tested.

The custom citation fixture initially triggered macOS Documents-folder access before its window loaded. It was exercised by launching the development executable from the already-authorized workspace shell; no global permissions were changed. Normal default-library launch and app-owned test-library restarts were checked independently. Drag-and-drop support is implemented through the same importer, but this pass used the native picker rather than an actual Finder drag.

## External verification still required

- Real Ollama generation, vision input, structured study generation, and cancellation require a running daemon and an installed compatible local model.
- Real OpenRouter generation, model support, billing, and cancellation require the student's own API key and applicable account access. No live inference was attempted without credentials.
- Public distribution signing and notarization are separate from a local development build.

Official provider contracts and setup references are collected in [PROVIDERS.md](PROVIDERS.md): [Ollama chat](https://docs.ollama.com/api/chat), [Ollama model listing](https://docs.ollama.com/api/tags), [OpenRouter quickstart](https://openrouter.ai/docs/quickstart), [OpenRouter streaming](https://openrouter.ai/docs/api_reference/streaming), and [OpenRouter structured outputs](https://openrouter.ai/docs/guides/features/structured-outputs).

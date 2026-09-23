# Implementation notes

Clevylo is a native SwiftUI/AppKit app with separate local persistence, document ingestion, source retrieval, provider networking, and study logic. It supports local models through Ollama and cloud models through OpenRouter.

## Decisions

- macOS 14 deployment target; system SwiftUI, AppKit, PDFKit, Vision, and Security frameworks. No third-party runtime dependencies.
- Atomic local JSON snapshots and UUID-named managed files. Failed destructive saves roll back metadata before any document copy is removed. Corrupt or newer snapshots are preserved and block writes.
- Date-only deadlines use Gregorian year/month/day in the user's timezone. Flashcard scheduling uses calendar days and records actual reviews.
- Immutable local lexical indexes rank passages from explicitly selected sources. References include stable passage identity and resolve against current content before opening.
- Ollama uses a fixed loopback endpoint and rejects cloud models; OpenRouter uses its fixed HTTPS endpoint. Model selection is explicit. No downloads, embedded keys, production fake provider, analytics, accounts, or hosted backend.
- OpenRouter credentials use device-local Keychain. Cloud sharing requires the student's settings consent. Imported text is untrusted reference data; model output has no tool or command execution path.

## Implemented

The app includes subjects, managed PDF/text/Markdown/image imports, embedded text and on-device OCR, an editable extraction viewer beside Tutor, searchable autosaved notes, linked assignments, streaming conversation history with source references, editable flashcards and quizzes, persistent reviews, real-activity Today, and native settings/menus/shortcuts.

Shared models connect ingestion, provider networking, and study features. Integration checks cover cancellation, source changes during generation, transactional deletion, note/source navigation, modal study state, and native keyboard review.

Build scripts account for Finder metadata attached to generated bundles in this file-provider-managed workspace. The default Release app uses local ad-hoc signing without test entitlements; Debug test bundles use the explicit local XCTest entitlements. Nothing is prepared for public distribution.

See [VERIFICATION.md](VERIFICATION.md) for actual build, automated test, manual interface evidence, and the remaining live-model checks.

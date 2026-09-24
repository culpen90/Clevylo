import AppKit
import XCTest
@testable import Clevylo

final class UpdaterTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClevyloUpdaterTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @MainActor
    func testTerminationFlushesPendingEditsBeforeAllowingRelaunch() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootURL: root)
        let subject = store.addSubject(name: "Biology")
        var note = Note(subjectID: subject.id, title: "Cell notes", text: "Saved draft")
        store.updateNote(note)
        XCTAssertTrue(store.saveNow())

        note.text = "The most recent edit must survive an update."
        store.updateNote(note)
        store.settings.model = "pending-model-change"
        XCTAssertEqual(try DiskStorage(root: root).loadLibrary().notes.first?.text, "Saved draft")

        let delegate = ClevyloApplicationDelegate()
        delegate.beforeTermination = { store.isReadOnly || store.saveNow() }
        delegate.showSaveFailure = { XCTFail("A successful save should not show an error.") }
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow)

        let reloaded = LibraryStore(rootURL: root)
        XCTAssertEqual(reloaded.library.notes, [note])
        XCTAssertEqual(reloaded.settings.model, "pending-model-change")
        XCTAssertEqual(store.saveStatus, "Saved locally")
    }

    @MainActor
    func testFailedSaveCancelsTerminationAndAllowsRetryAfterRecovery() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootURL: root)
        let subject = store.addSubject(name: "History")
        var note = Note(subjectID: subject.id, title: "Draft", text: "Previous saved content")
        store.updateNote(note)
        XCTAssertTrue(store.saveNow())

        // A directory at the settings file path reliably simulates an unwritable
        // save destination, including when tests run with broad filesystem access.
        let settingsURL = root.appendingPathComponent("settings.json")
        try FileManager.default.removeItem(at: settingsURL)
        try FileManager.default.createDirectory(at: settingsURL, withIntermediateDirectories: false)
        note.text = "Keep this unsaved edit available until saving succeeds."
        store.updateNote(note)

        var failuresShown = 0
        let delegate = ClevyloApplicationDelegate()
        delegate.beforeTermination = { store.isReadOnly || store.saveNow() }
        delegate.showSaveFailure = { failuresShown += 1 }
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateCancel)
        XCTAssertEqual(failuresShown, 1)
        XCTAssertEqual(store.library.notes, [note], "Cancelling an update must preserve the pending edit in memory.")
        XCTAssertEqual(try DiskStorage(root: root).loadLibrary().notes.first?.text, "Previous saved content")
        XCTAssertEqual(store.saveStatus, "Could not save")

        try FileManager.default.removeItem(at: settingsURL)
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow)
        XCTAssertEqual(failuresShown, 1)
        XCTAssertEqual(try DiskStorage(root: root).loadLibrary().notes, [note])
    }

    @MainActor
    func testReadOnlyLibraryCanQuitWithoutOverwritingPreservedData() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let libraryURL = root.appendingPathComponent("library.json")
        let preservedData = Data("{existing library that cannot be decoded".utf8)
        try preservedData.write(to: libraryURL)
        let store = LibraryStore(rootURL: root)
        XCTAssertTrue(store.isReadOnly)

        let delegate = ClevyloApplicationDelegate()
        delegate.beforeTermination = { store.isReadOnly || store.saveNow() }
        delegate.showSaveFailure = { XCTFail("A preserved, read-only library must not trap the user in the app.") }
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow)
        XCTAssertEqual(try Data(contentsOf: libraryURL), preservedData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("settings.json").path))
    }

    @MainActor
    func testBundledUpdaterRequiresAuthenticatedFeedAndArchive() throws {
        // Inspect the built application rather than the source plist so this also
        // catches packaging or generated Info.plist settings that drop protection.
        let bundle = Bundle(for: ClevyloApplicationDelegate.self)
        let feed = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)
        XCTAssertEqual(feed, "https://github.com/culpen90/Clevylo/releases/latest/download/appcast.xml")
        let publicKey = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
        XCTAssertEqual(Data(base64Encoded: publicKey)?.count, 32, "The app needs an Ed25519 public key to verify releases.")
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool, true)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool, true)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUSignedFeedFailureExpirationInterval") as? Int, 0)
    }

    @MainActor
    func testBundledUpdaterKeepsInstallationManualAndDisablesProfiling() {
        let bundle = Bundle(for: ClevyloApplicationDelegate.self)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") as? Bool, false)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUAllowsAutomaticUpdates") as? Bool, false)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUEnableSystemProfiling") as? Bool, false)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUEnableJavaScript") as? Bool, false)
        XCTAssertNil(bundle.object(forInfoDictionaryKey: "SUEnableAutomaticChecks"), "Sparkle should ask before enabling automatic checks.")
    }
}

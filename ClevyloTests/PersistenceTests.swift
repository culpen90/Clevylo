import XCTest
@testable import Clevylo

final class PersistenceTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClevyloPersistenceTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @MainActor
    func testCompleteTwoSubjectWorkspaceRoundTripsWithoutMixingContent() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootURL: root)
        let biology = store.addSubject(name: "Biology", color: "green", symbol: "leaf")
        let algebra = store.addSubject(name: "Algebra", color: "purple", symbol: "function")
        for (subject, lesson) in [(biology, "Cell membranes control transport."), (algebra, "Linear equations have constant slope.")] {
            let source = root.appendingPathComponent(subject.id.uuidString + ".txt")
            try Data(lesson.utf8).write(to: source)
            let material = try await DocumentImporter.importFile(at: source, subjectID: subject.id, into: store.materialsURL)
            store.library.materials.append(material)
            store.updateNote(Note(subjectID: subject.id, title: subject.name + " notes", text: lesson))
            store.updateAssignment(Assignment(subjectID: subject.id, title: subject.name + " homework", instructions: "Explain the lesson.", dueDate: LocalDay(year: 2026, month: 10, day: 2), materialIDs: [material.id]))
            let sources = SourceIndex(library: store.library).retrieve(query: lesson, materialIDs: [material.id], noteIDs: [], assignmentIDs: [])
            store.library.conversations.append(Conversation(subjectID: subject.id, title: subject.name + " question", messages: [ChatMessage(role: "user", text: "Explain this."), ChatMessage(role: "assistant", text: lesson + " [S1]", sources: sources)]))
            let card = Flashcard(front: "Explain the central idea.", back: lesson, dueDate: LocalDay(year: 2026, month: 10, day: 3), intervalDays: 3, reviewCount: 1)
            store.updateStudySet(StudySet(subjectID: subject.id, title: subject.name + " practice", kind: .flashcards, cards: [card], reviews: [ReviewEvent(cardID: card.id, rating: "easy")]))
            try FileManager.default.removeItem(at: source)
        }
        store.settings = AISettings(provider: .openRouter, model: "example/model", cloudConsent: true)
        store.saveNow()
        XCTAssertNil(store.errorMessage)
        let reloaded = LibraryStore(rootURL: root)
        XCTAssertEqual(reloaded.library, store.library)
        XCTAssertEqual(reloaded.settings, store.settings)
        XCTAssertEqual(reloaded.library.subjects.count, 2)
        for subject in [biology, algebra] {
            let materials = reloaded.library.materials.filter { $0.subjectID == subject.id }
            XCTAssertEqual(materials.count, 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: reloaded.materialURL(try XCTUnwrap(materials.first)).path))
            XCTAssertEqual(reloaded.library.notes.filter { $0.subjectID == subject.id }.count, 1)
            XCTAssertEqual(reloaded.library.assignments.filter { $0.subjectID == subject.id }.first?.materialIDs, materials.map(\.id))
            XCTAssertEqual(reloaded.library.studySets.filter { $0.subjectID == subject.id }.first?.reviews.count, 1)
            let references = SourceIndex(library: reloaded.library).retrieve(query: "Explain this", materialIDs: Set(materials.map(\.id)), noteIDs: [], assignmentIDs: [])
            XCTAssertTrue(references.allSatisfy { $0.materialID == materials.first?.id })
        }
        let serializedSettings = try String(contentsOf: root.appendingPathComponent("settings.json"), encoding: .utf8)
        XCTAssertFalse(serializedSettings.contains("apiKey"))
    }

    @MainActor
    func testAssignmentEditsAndCompletionOnlyChangeTheMatchingID() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootURL: root)
        let subject = store.addSubject(name: "History")
        let first = Assignment(subjectID: subject.id, title: "Essay", instructions: "Draft thesis.", dueDate: LocalDay(year: 2026, month: 9, day: 24))
        let second = Assignment(subjectID: subject.id, title: "Essay", instructions: "Read chapter two.", dueDate: LocalDay(year: 2026, month: 9, day: 25))
        store.updateAssignment(first)
        store.updateAssignment(second)
        var edited = first
        edited.title = "Revised essay"
        edited.instructions = "Complete the draft."
        edited.dueDate = LocalDay(year: 2026, month: 10, day: 1)
        edited.isComplete = true
        store.updateAssignment(edited)
        store.saveNow()
        let reloaded = LibraryStore(rootURL: root)
        XCTAssertEqual(reloaded.library.assignments.count, 2)
        XCTAssertEqual(reloaded.library.assignments.first { $0.id == edited.id }, edited)
        XCTAssertEqual(reloaded.library.assignments.first { $0.id == second.id }, second)
        XCTAssertEqual(reloaded.library.assignments.filter { !$0.isComplete }.map(\.id), [second.id])
    }

    func testDateOnlyDeadlinesSurviveTimeZonesAndDaylightSaving() throws {
        let expected = LocalDay(year: 2026, month: 11, day: 1)
        let encoded = try JSONEncoder().encode(expected)
        for zone in ["America/New_York", "Pacific/Kiritimati", "Pacific/Honolulu", "Europe/London", "Asia/Kathmandu"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
            let decoded = try JSONDecoder().decode(LocalDay.self, from: encoded)
            XCTAssertEqual(decoded, expected)
            XCTAssertEqual(LocalDay(decoded.date(calendar: calendar), calendar: calendar), expected, zone)
            XCTAssertEqual(decoded.adding(days: 1, calendar: calendar), LocalDay(year: 2026, month: 11, day: 2), zone)
            XCTAssertEqual(decoded.adding(days: -1, calendar: calendar), LocalDay(year: 2026, month: 10, day: 31), zone)
        }
        XCTAssertTrue(LocalDay(year: 2026, month: 12, day: 31) < LocalDay(year: 2027, month: 1, day: 1))
    }

    func testConvertingAnInstantUsesTheRequestedLocalDay() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-24T00:30:00Z"))
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        XCTAssertEqual(LocalDay(instant, calendar: eastern), LocalDay(year: 2026, month: 9, day: 23))
        XCTAssertEqual(LocalDay(instant, calendar: tokyo), LocalDay(year: 2026, month: 9, day: 24))
    }

    @MainActor
    func testCorruptLibraryIsReportedAndNeverOverwritten() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("{broken existing library".utf8)
        let file = root.appendingPathComponent("library.json")
        try original.write(to: file)
        let store = LibraryStore(rootURL: root)
        XCTAssertNotNil(store.errorMessage)
        _ = store.addSubject(name: "Must not overwrite old data")
        store.saveNow()
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    @MainActor
    func testNewerLibrarySchemaIsPreserved() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var library = Library(subjects: [Subject(name: "Future version")])
        library.schemaVersion = 999
        let original = try JSONEncoder().encode(library)
        let file = root.appendingPathComponent("library.json")
        try original.write(to: file)
        let store = LibraryStore(rootURL: root)
        XCTAssertNotNil(store.errorMessage)
        store.saveNow()
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    @MainActor
    func testCorruptSettingsCannotMakeDeletionDestroyPreservedMaterial() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try DiskStorage(root: root)
        let material = Material(subjectID: UUID(), name: "Keep me", storedFilename: UUID().uuidString + ".txt", pages: [MaterialPage(number: 1, text: "Keep this content.")], kind: "text")
        try storage.save(Library(materials: [material]), settings: AISettings())
        let file = root.appendingPathComponent("Materials").appendingPathComponent(material.storedFilename)
        try Data("Keep this content.".utf8).write(to: file)
        let originalLibrary = try Data(contentsOf: root.appendingPathComponent("library.json"))
        try Data("broken settings".utf8).write(to: root.appendingPathComponent("settings.json"))
        let store = LibraryStore(rootURL: root)
        XCTAssertNotNil(store.errorMessage)
        store.deleteMaterial(material)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "Unavailable library must never delete originals it cannot save.")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library.json")), originalLibrary)
    }

    @MainActor
    func testFailedMetadataSaveDoesNotDeleteManagedFile() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootURL: root)
        let material = Material(subjectID: UUID(), name: "Keep me", storedFilename: UUID().uuidString + ".txt", pages: [MaterialPage(number: 1, text: "Retain this file.")], kind: "text")
        store.library.materials.append(material)
        let file = store.materialURL(material)
        try Data("Retain this file.".utf8).write(to: file)
        store.saveNow()
        let libraryURL = root.appendingPathComponent("library.json")
        try FileManager.default.removeItem(at: libraryURL)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: false)
        store.deleteMaterial(material)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "A failed metadata save must not delete its managed document.")
        XCTAssertTrue(store.library.materials.contains { $0.id == material.id }, "Failed deletion should leave the material available for recovery.")
        store.saveNow()
    }

    @MainActor
    func testFailedSettingsSaveDoesNotCommitDestructiveLibraryMetadata() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootURL: root)
        let material = Material(subjectID: UUID(), name: "Keep me", storedFilename: UUID().uuidString + ".txt", pages: [MaterialPage(number: 1, text: "Retain this file.")], kind: "text")
        store.library.materials.append(material)
        try Data("Retain this file.".utf8).write(to: store.materialURL(material))
        store.saveNow()
        let settingsURL = root.appendingPathComponent("settings.json")
        try FileManager.default.removeItem(at: settingsURL)
        try FileManager.default.createDirectory(at: settingsURL, withIntermediateDirectories: false)
        store.deleteMaterial(material)
        XCTAssertNotNil(store.errorMessage)
        let disk = try DiskStorage(root: root)
        XCTAssertEqual(try disk.loadLibrary().materials, [material], "A failed transaction must preserve the last saved metadata.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.materialURL(material).path))
        store.saveNow()
    }

    @MainActor
    func testDeletingMaterialCleansFileAttachmentsAndCitationsOnlyForThatMaterial() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootURL: root)
        let subject = store.addSubject(name: "Science")
        let first = Material(subjectID: subject.id, name: "First", storedFilename: UUID().uuidString + ".txt", pages: [MaterialPage(number: 1, text: "First lesson.")], kind: "text")
        let second = Material(subjectID: subject.id, name: "Second", storedFilename: UUID().uuidString + ".txt", pages: [MaterialPage(number: 1, text: "Second lesson.")], kind: "text")
        store.library.materials = [first, second]
        for material in [first, second] { try Data(material.name.utf8).write(to: store.materialURL(material)) }
        store.updateAssignment(Assignment(subjectID: subject.id, title: "Review", materialIDs: [first.id, second.id]))
        let sources = SourceIndex(library: store.library).retrieve(query: "Explain this", materialIDs: [first.id, second.id], noteIDs: [], assignmentIDs: [])
        store.library.conversations = [Conversation(subjectID: subject.id, messages: [ChatMessage(role: "assistant", text: "Two lessons.", sources: sources)])]
        store.saveNow()
        store.deleteMaterial(first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.materialURL(first).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.materialURL(second).path))
        let reloaded = LibraryStore(rootURL: root)
        XCTAssertEqual(reloaded.library.materials, [second])
        XCTAssertEqual(reloaded.library.assignments[0].materialIDs, [second.id])
        XCTAssertEqual(reloaded.library.conversations[0].messages[0].sources.compactMap(\.materialID), [second.id])
        XCTAssertFalse(SourceIndex(library: reloaded.library).resolves(try XCTUnwrap(sources.first { $0.materialID == first.id })))
    }

    @MainActor
    func testDeletingSubjectPreservesOtherSubjectContentAndFiles() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootURL: root)
        let first = store.addSubject(name: "First")
        let second = store.addSubject(name: "Second")
        for subject in [first, second] {
            let material = Material(subjectID: subject.id, name: subject.name, storedFilename: UUID().uuidString + ".txt", pages: [MaterialPage(number: 1, text: subject.name)], kind: "text")
            try Data(subject.name.utf8).write(to: store.materialURL(material))
            store.library.materials.append(material)
            store.updateNote(Note(subjectID: subject.id, text: subject.name))
            store.updateAssignment(Assignment(subjectID: subject.id, title: subject.name, materialIDs: [material.id]))
            store.updateStudySet(StudySet(subjectID: subject.id, title: subject.name, kind: .flashcards, cards: [Flashcard(front: "Q", back: "A")]))
            store.library.conversations.append(Conversation(subjectID: subject.id, title: subject.name))
        }
        store.saveNow()
        let retained = store.library.materials.first { $0.subjectID == second.id }!
        let removed = store.library.materials.first { $0.subjectID == first.id }!
        store.deleteSubject(first.id)
        let reloaded = LibraryStore(rootURL: root)
        XCTAssertEqual(reloaded.library.subjects, [second])
        XCTAssertEqual(reloaded.library.materials.map(\.subjectID), [second.id])
        XCTAssertEqual(reloaded.library.notes.map(\.subjectID), [second.id])
        XCTAssertEqual(reloaded.library.assignments.map(\.subjectID), [second.id])
        XCTAssertEqual(reloaded.library.studySets.compactMap(\.subjectID), [second.id])
        XCTAssertEqual(reloaded.library.conversations.compactMap(\.subjectID), [second.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.materialURL(removed).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.materialURL(retained).path))
    }

    @MainActor
    func testSubjectDeletionValidatesAllMaterialsBeforeRemovingAnything() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootURL: root)
        let subject = store.addSubject(name: "Keep complete subject")
        let safe = Material(subjectID: subject.id, name: "Safe", storedFilename: UUID().uuidString + ".txt", pages: [MaterialPage(number: 1, text: "Preserve me")], kind: "text")
        let unsafe = Material(subjectID: subject.id, name: "Invalid reference", storedFilename: "..", pages: [], kind: "text")
        try Data("Preserve me".utf8).write(to: store.materialURL(safe))
        store.library.materials = [safe, unsafe]
        store.updateNote(Note(subjectID: subject.id, text: "Retain notes too."))
        store.saveNow()
        let original = store.library
        store.deleteSubject(subject.id)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.library, original)
        XCTAssertEqual(try DiskStorage(root: root).loadLibrary(), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.materialURL(safe).path))
        store.saveNow()
    }

    @MainActor
    func testSubjectDeletionRollsBackWholeWorkspaceOnSaveFailure() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootURL: root)
        let subject = store.addSubject(name: "Keep complete subject")
        let material = Material(subjectID: subject.id, name: "Keep", storedFilename: UUID().uuidString + ".txt", pages: [], kind: "text")
        try Data("Preserve me".utf8).write(to: store.materialURL(material))
        store.library.materials = [material]
        store.updateNote(Note(subjectID: subject.id, text: "Preserve notes."))
        store.updateAssignment(Assignment(subjectID: subject.id, title: "Preserve assignment", materialIDs: [material.id]))
        store.saveNow()
        let original = store.library
        let libraryURL = root.appendingPathComponent("library.json")
        try FileManager.default.removeItem(at: libraryURL)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: false)
        store.deleteSubject(subject.id)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.library, original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.materialURL(material).path))
        store.saveNow()
    }

    @MainActor
    func testMalformedStoredFilenameCannotDeleteMaterialDirectoryOrLibraryRoot() async throws {
        for filename in [".", "..", "../..", "/", "subfolder/file.txt", "\\.."] {
            let root = try temporaryRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = LibraryStore(rootURL: root)
            let sentinel = root.appendingPathComponent("keep.txt")
            try Data("Preserve workspace".utf8).write(to: sentinel)
            let invalid = Material(subjectID: UUID(), name: "Invalid snapshot entry", storedFilename: filename, pages: [], kind: "text")
            store.library.materials = [invalid]
            store.saveNow()
            store.deleteMaterial(invalid)
            XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path), filename)
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.materialsURL.path), filename)
            store.saveNow()
        }
    }

    @MainActor
    func testInterruptedStreamIsExplicitlyMarkedAfterRestart() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try DiskStorage(root: root)
        let complete = ChatMessage(role: "user", text: "Explain cells.")
        let partial = ChatMessage(role: "assistant", text: "Cells are", status: "streaming")
        try storage.save(Library(conversations: [Conversation(messages: [complete, partial])]), settings: AISettings())
        let reloaded = LibraryStore(rootURL: root)
        XCTAssertEqual(reloaded.library.conversations[0].messages[0], complete)
        XCTAssertEqual(reloaded.library.conversations[0].messages[1].status, "interrupted")
        XCTAssertEqual(reloaded.library.conversations[0].messages[1].text, "Cells are")
        reloaded.saveNow()
        XCTAssertEqual(try storage.loadLibrary().conversations[0].messages[1].status, "interrupted")
    }

    @MainActor
    func testOpeningNoteAndAssignmentDismissesDocumentWorkspace() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootURL: root)
        let first = store.addSubject(name: "Biology")
        let second = store.addSubject(name: "Algebra")
        let note = Note(subjectID: first.id, title: "Cell notes", text: "A cell is a unit of life.")
        let assignment = Assignment(subjectID: second.id, title: "Linear equations")
        store.updateNote(note)
        store.updateAssignment(assignment)

        store.route = .tutor
        store.openedMaterial = MaterialLocation(id: UUID(), page: 2)
        store.openNote(note)
        XCTAssertNil(store.openedMaterial, "The document sheet must close so the selected note is visible.")
        XCTAssertEqual(store.openedNoteID, note.id)
        XCTAssertEqual(store.route, .subject(first.id))

        store.openedNoteID = nil // SubjectView consumes the pending destination.
        store.route = .tutor
        store.openedMaterial = MaterialLocation(id: UUID(), page: 3)
        store.openAssignment(assignment)
        XCTAssertNil(store.openedMaterial, "The document sheet must close so the assignment can open.")
        XCTAssertEqual(store.openedAssignmentID, assignment.id)
        XCTAssertEqual(store.route, .subject(second.id))
        store.saveNow()
    }

    @MainActor
    func testDebouncedNoteAutosaveActuallyReachesDisk() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootURL: root)
        let subject = store.addSubject(name: "Notes")
        var note = Note(subjectID: subject.id, title: "Draft", text: "First")
        store.updateNote(note)
        note.text = "The final edit must be saved."
        store.updateNote(note)
        let storage = try DiskStorage(root: root)
        var saved: Library?
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if let loaded = try? storage.loadLibrary(), loaded.notes.first?.text == note.text {
                saved = loaded
                break
            }
        }
        XCTAssertEqual(saved?.notes, [note])
        store.saveNow()
    }
}

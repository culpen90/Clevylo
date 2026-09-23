import XCTest
import CoreGraphics
import CoreText
import ImageIO
@testable import Clevylo

final class IngestionTests: XCTestCase {
    private var root: URL!
    private var managed: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ClevyloIngestionTests-" + UUID().uuidString, isDirectory: true)
        managed = root.appendingPathComponent("Managed", isDirectory: true)
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func fixture(_ name: String, text: String = "Cell membranes control transport.") throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func managedFiles() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: managed.path) }

    func testManagedCopiesSurviveOriginalDeletionAndDuplicateNames() async throws {
        let originalA = try fixture("a/lesson.md", text: "First lesson about cells.")
        let originalB = try fixture("b/lesson.md", text: "Second lesson about planets.")
        let subjectA = UUID(), subjectB = UUID()
        let first = try await DocumentImporter.importFile(at: originalA, subjectID: subjectA, into: managed)
        let second = try await DocumentImporter.importFile(at: originalB, subjectID: subjectB, into: managed)
        XCTAssertEqual(first.name, second.name)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.storedFilename, second.storedFilename)
        XCTAssertEqual(first.storedFilename, first.id.uuidString + ".md")
        XCTAssertEqual(first.subjectID, subjectA)
        XCTAssertEqual(second.subjectID, subjectB)
        try FileManager.default.removeItem(at: originalA)
        XCTAssertEqual(try String(contentsOf: managed.appendingPathComponent(first.storedFilename), encoding: .utf8), "First lesson about cells.")
        XCTAssertEqual(try managedFiles().count, 2)
    }

    func testInvalidFormatAndMalformedInputsLeaveNoManagedFiles() async throws {
        let invalid = try fixture("script.exe")
        let pdf = try fixture("broken.pdf", text: "This is not a PDF.")
        let image = try fixture("broken.png", text: "This is not an image.")
        let text = try fixture("binary.txt")
        try Data([0xFF, 0x80, 0xFF, 0x80]).write(to: text)
        for file in [invalid, pdf, image, text] {
            do {
                _ = try await DocumentImporter.importFile(at: file, subjectID: UUID(), into: managed)
                XCTFail("Expected invalid import to fail: \(file.lastPathComponent)")
            } catch { XCTAssertFalse(error is CancellationError) }
        }
        XCTAssertTrue(try managedFiles().isEmpty)
    }

    func testRejectsDirectoriesEvenWithSupportedExtension() async throws {
        let directory = root.appendingPathComponent("folder.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            _ = try await DocumentImporter.importFile(at: directory, subjectID: UUID(), into: managed)
            XCTFail("Expected a directory to be rejected")
        } catch { XCTAssertTrue(error is DocumentImportError) }
        XCTAssertTrue(try managedFiles().isEmpty)
    }

    func testUTF16AndEmptyTextAreHandledExplicitly() async throws {
        let unicode = try fixture("unicode.txt")
        try XCTUnwrap("Euler: π and café".data(using: .utf16)).write(to: unicode)
        let material = try await DocumentImporter.importFile(at: unicode, subjectID: UUID(), into: managed)
        XCTAssertEqual(material.pages[0].text, "Euler: π and café")
        let empty = try fixture("empty.txt", text: "\n \n")
        let emptyMaterial = try await DocumentImporter.importFile(at: empty, subjectID: UUID(), into: managed)
        XCTAssertNotNil(emptyMaterial.pages[0].warning)
        XCTAssertNotNil(emptyMaterial.warning)
    }

    func testFileSizeLimitRejectsWithoutCopying() async throws {
        let oversized = try fixture("oversized.txt")
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(DocumentImporter.maximumFileBytes + 1))
        try handle.close()
        do {
            _ = try await DocumentImporter.importFile(at: oversized, subjectID: UUID(), into: managed)
            XCTFail("Expected size limit")
        } catch DocumentImportError.tooLarge {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(try managedFiles().isEmpty)
    }

    func testTextCharacterLimitRemovesCopiedFile() async throws {
        let large = try fixture("too-long.txt", text: String(repeating: "a", count: DocumentImporter.maximumTextCharacters + 1))
        do {
            _ = try await DocumentImporter.importFile(at: large, subjectID: UUID(), into: managed)
            XCTFail("Expected character limit")
        } catch DocumentImportError.tooMuchText {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(try managedFiles().isEmpty)
    }

    func testCancelledImportLeavesNoCopy() async throws {
        let source = try fixture("cancel.txt", text: String(repeating: "Study text. ", count: 100_000))
        let directory = managed!
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await DocumentImporter.importFile(at: source, subjectID: UUID(), into: directory)
        }
        do {
            _ = try await operation.value
            XCTFail("Cancelled import must throw")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(try managedFiles().isEmpty)
    }

    func testCancellationDuringImportCleansUp() async throws {
        let source = try fixture("cancel-large.txt", text: String(repeating: "biology ", count: 200_000))
        let directory = managed!
        let operation = Task { try await DocumentImporter.importFile(at: source, subjectID: UUID(), into: directory) }
        // Cancel promptly while detached work is starting; cancellation is safe at
        // either side of the managed-copy boundary.
        await Task.yield()
        operation.cancel()
        do {
            let completed = try await operation.value
            // If it completed before cancellation, it is a valid completed import.
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(completed.storedFilename).path))
        } catch is CancellationError {
            XCTAssertTrue(try managedFiles().isEmpty)
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testPDFUsesEmbeddedTextBeforeOCR() async throws {
        let pdf = try makePDF(name: "embedded.pdf", texts: ["Photosynthesis converts light into energy.", "Second page describes chlorophyll."])
        let material = try await DocumentImporter.importFile(at: pdf, subjectID: UUID(), into: managed)
        XCTAssertEqual(material.pages.map(\.number), [1, 2])
        XCTAssertTrue(material.pages[0].text.contains("Photosynthesis"))
        XCTAssertTrue(material.pages.allSatisfy { !$0.usedOCR && $0.warning == nil })
        XCTAssertNil(material.warning)
    }

    func testPDFPageLimitIsEnforcedBeforeRecognition() async throws {
        let pdf = try makePDF(name: "too-many.pdf", texts: Array(repeating: "", count: DocumentImporter.maximumPDFPages + 1))
        do {
            _ = try await DocumentImporter.importFile(at: pdf, subjectID: UUID(), into: managed)
            XCTFail("Expected PDF page limit")
        } catch DocumentImportError.tooManyPages {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(try managedFiles().isEmpty)
    }

    func testBlankScannedPageIsNeverPresentedAsUnderstood() async throws {
        let pdf = try makePDF(name: "blank.pdf", texts: [""])
        let material = try await DocumentImporter.importFile(at: pdf, subjectID: UUID(), into: managed)
        XCTAssertTrue(material.pages[0].usedOCR)
        XCTAssertTrue(material.pages[0].text.isEmpty)
        XCTAssertNotNil(material.pages[0].warning)
        XCTAssertNotNil(material.warning)
        let index = SourceIndex(library: Library(materials: [material]))
        XCTAssertTrue(index.retrieve(query: "Explain this", materialIDs: [material.id], noteIDs: [], assignmentIDs: []).isEmpty)
    }

    func testImageRecognitionFlagsMathUncertainty() async throws {
        let url = root.appendingPathComponent("worksheet.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 1200, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 600))
        draw("Study the water cycle.", at: CGPoint(x: 60, y: 300), in: context, size: 48)
        let image = try XCTUnwrap(context.makeImage())
        let output = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(output, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(output))
        let material = try await DocumentImporter.importFile(at: url, subjectID: UUID(), into: managed)
        XCTAssertTrue(material.pages[0].usedOCR)
        XCTAssertTrue(material.pages[0].text.lowercased().contains("water"))
        XCTAssertTrue(material.pages[0].warning?.contains("equations") == true)
    }

    func testRetrievalNeverIncludesUnselectedSourcesOrRelatedAssignmentMaterials() {
        let subjectA = UUID(), subjectB = UUID()
        let first = Material(subjectID: subjectA, name: "Biology", storedFilename: "a.txt", pages: [MaterialPage(number: 1, text: "Mitochondria produce energy in cells.")], kind: "text")
        let second = Material(subjectID: subjectB, name: "Private biology", storedFilename: "b.txt", pages: [MaterialPage(number: 1, text: "Mitochondria contain secret subject notes.")], kind: "text")
        let note = Note(subjectID: subjectB, title: "Hidden note", text: "Mitochondria facts.")
        let assignment = Assignment(subjectID: subjectA, title: "Explain cells", instructions: "Describe their energy supply.", materialIDs: [second.id])
        let index = SourceIndex(library: Library(materials: [first, second], notes: [note], assignments: [assignment]))
        XCTAssertTrue(index.retrieve(query: "Mitochondria", materialIDs: [], noteIDs: [], assignmentIDs: []).isEmpty)
        let selected = index.retrieve(query: "Mitochondria", materialIDs: [first.id], noteIDs: [], assignmentIDs: [])
        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected[0].materialID, first.id)
        let assignmentOnly = index.retrieve(query: "energy", materialIDs: [], noteIDs: [], assignmentIDs: [assignment.id])
        XCTAssertTrue(assignmentOnly.allSatisfy { $0.assignmentID == assignment.id && $0.materialID == nil })
    }

    func testLexicalRetrievalRanksRelevantPagesAndPreservesStableIdentity() {
        let material = Material(subjectID: UUID(), name: "Science", storedFilename: "s.pdf", pages: [
            MaterialPage(number: 1, text: "Plants have leaves and roots."),
            MaterialPage(number: 2, text: "The nucleus contains genetic DNA information.")
        ], kind: "pdf")
        let library = Library(materials: [material])
        let query = SourceIndex(library: library).retrieve(query: "nucleus DNA", materialIDs: [material.id], noteIDs: [], assignmentIDs: [])
        XCTAssertEqual(query.first?.page, 2)
        XCTAssertEqual(query.first?.id, "S1")
        let repeated = SourceIndex(library: library).retrieve(query: "nucleus DNA", materialIDs: [material.id], noteIDs: [], assignmentIDs: [])
        XCTAssertEqual(query.first?.passageID, repeated.first?.passageID)
        XCTAssertEqual(query, repeated)
    }

    func testGenericQuestionsGetRepresentativePassagesFromSelectedSources() {
        let first = Note(subjectID: UUID(), title: "Cells", text: String(repeating: "Cells store energy. ", count: 200))
        let second = Note(subjectID: UUID(), title: "Planets", text: "Planets orbit stars.")
        let index = SourceIndex(library: Library(notes: [first, second]))
        let references = index.retrieve(query: "Explain this", materialIDs: [], noteIDs: [first.id, second.id], assignmentIDs: [], limit: 2)
        XCTAssertEqual(Set(references.compactMap(\.noteID)), [first.id, second.id])
        XCTAssertTrue(references.allSatisfy { $0.excerpt.count <= 1600 })
    }

    func testOnlyExactCandidateCitationTokensResolve() {
        let note = Note(subjectID: UUID(), title: "My notes", text: "Gravity attracts objects with mass.")
        let index = SourceIndex(library: Library(notes: [note]))
        let candidates = index.retrieve(query: "gravity", materialIDs: [], noteIDs: [note.id], assignmentIDs: [])
        XCTAssertEqual(index.validatedReferences(in: "Gravity attracts [S1]. Again [S1].", candidates: candidates).count, 1)
        for invalid in ["S1", "[S2]", "[S10]", "[S01]", "[s1]", "[S1 extra]", "[S1,S2]", "[[S1]]", #"\[S1]"#] {
            XCTAssertTrue(index.validatedReferences(in: invalid, candidates: candidates).isEmpty, invalid)
        }
        XCTAssertTrue(index.validatedReferences(in: "[S1]", candidates: candidates + candidates).isEmpty)
        var invented = candidates[0]
        invented.excerpt = "The model invented this."
        XCTAssertTrue(index.validatedReferences(in: "[S1]", candidates: [invented]).isEmpty)
        invented = candidates[0]
        invented.noteID = UUID()
        XCTAssertFalse(index.resolves(invented))
    }

    func testDeletingOrEditingSourcesInvalidatesSavedCitations() throws {
        var note = Note(subjectID: UUID(), title: "Original title", text: "Original passage about ecosystems.")
        let index = SourceIndex(library: Library(notes: [note]))
        let source = try XCTUnwrap(index.retrieve(query: "ecosystems", materialIDs: [], noteIDs: [note.id], assignmentIDs: []).first)
        XCTAssertTrue(index.resolves(source))
        note.title = "Renamed title"
        let renamed = SourceIndex(library: Library(notes: [note]))
        XCTAssertEqual(renamed.currentReference(source)?.title, "Renamed title")
        note.text = "Replacement passage about chemistry."
        XCTAssertFalse(SourceIndex(library: Library(notes: [note])).resolves(source))
        let deleted = SourceIndex(library: Library())
        XCTAssertFalse(deleted.resolves(source))
        XCTAssertTrue(deleted.validatedReferences(in: "[S1]", candidates: [source]).isEmpty)
        XCTAssertTrue(deleted.retrieve(query: "ecosystems", materialIDs: [], noteIDs: [note.id], assignmentIDs: []).isEmpty)
    }

    private func makePDF(name: String, texts: [String]) throws -> URL {
        let url = root.appendingPathComponent(name)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        for text in texts {
            context.beginPDFPage(nil)
            if !text.isEmpty { draw(text, at: CGPoint(x: 40, y: 700), in: context, size: 16) }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    private func draw(_ text: String, at point: CGPoint, in context: CGContext, size: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        context.textPosition = point
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
    }
}

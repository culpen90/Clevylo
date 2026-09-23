import Foundation
import Combine

struct AppError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

final class DiskStorage {
    let root: URL
    private let queue = DispatchQueue(label: "com.clevylo.persistence", qos: .utility)
    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Materials"), withIntermediateDirectories: true)
    }
    func loadLibrary() throws -> Library {
        let url = root.appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return Library() }
        let library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: url))
        guard library.schemaVersion == 1 else { throw AppError("This library was created by a newer version of Clevylo. Update the app before opening it.") }
        return library
    }
    func loadSettings() throws -> AISettings {
        let url = root.appendingPathComponent("settings.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return AISettings() }
        return try JSONDecoder().decode(AISettings.self, from: Data(contentsOf: url))
    }
    private func write(_ library: Library, settings: AISettings) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: root.appendingPathComponent("settings.json"), options: .atomic)
        try encoder.encode(library).write(to: root.appendingPathComponent("library.json"), options: .atomic)
    }
    func save(_ library: Library, settings: AISettings) throws {
        try queue.sync { try write(library, settings: settings) }
    }
    func saveAsync(_ library: Library, settings: AISettings, completion: @escaping (Error?) -> Void) {
        queue.async {
            do { try self.write(library, settings: settings); completion(nil) }
            catch { completion(error) }
        }
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published var library: Library { didSet {
        scheduleSave()
        if library.materials != oldValue.materials || library.notes != oldValue.notes || library.assignments != oldValue.assignments { rebuildIndex() }
    } }
    @Published var settings: AISettings { didSet { scheduleSave() } }
    @Published var errorMessage: String?
    @Published var saveStatus = "Saved locally"
    @Published var importStatus: String?
    @Published var route: AppRoute = .today
    @Published var tutorLaunch: TutorLaunch?
    @Published var openedMaterial: MaterialLocation?
    @Published var openedNoteID: UUID?
    @Published var openedAssignmentID: UUID?
    @Published private(set) var isReadOnly = false
    @Published private(set) var sourceIndex: SourceIndex?
    let rootURL: URL
    var materialsURL: URL { rootURL.appendingPathComponent("Materials") }
    private var disk: DiskStorage?
    private var saveTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?
    private var writable = true

    init(rootURL: URL? = nil) {
        let args = ProcessInfo.processInfo.arguments
        let override: URL? = args.firstIndex(of: "--data-dir").flatMap { i in i + 1 < args.count ? URL(fileURLWithPath: args[i + 1], isDirectory: true) : nil }
        let environmentRoot = ProcessInfo.processInfo.environment["CLEVYLO_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        self.rootURL = rootURL ?? override ?? environmentRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Clevylo", isDirectory: true)
        library = Library(); settings = AISettings()
        do {
            let storage = try DiskStorage(root: self.rootURL)
            library = try storage.loadLibrary()
            settings = try storage.loadSettings()
            disk = storage
            // Interrupted responses remain explicitly incomplete after restart.
            for c in library.conversations.indices {
                for m in library.conversations[c].messages.indices where library.conversations[c].messages[m].status == "streaming" {
                    library.conversations[c].messages[m].status = "interrupted"
                }
            }
        } catch {
            writable = false
            isReadOnly = true
            errorMessage = "Could not open your local library. Existing files have been preserved. \(error.localizedDescription)\nLocation: \(self.rootURL.path)"
            saveStatus = "Library unavailable — files preserved"
        }
        rebuildIndex()
    }

    private func rebuildIndex() {
        sourceIndex = nil; indexTask?.cancel()
        let snapshot = library
        indexTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            let index = await Task.detached(priority: .utility) { SourceIndex(library: snapshot) }.value
            guard !Task.isCancelled else { return }
            self?.sourceIndex = index
        }
    }

    private func scheduleSave() {
        guard writable, disk != nil else { return }
        saveStatus = "Saving…"
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            guard let self else { return }
            self.disk?.saveAsync(self.library, settings: self.settings) { [weak self] error in
                Task { @MainActor in
                    if let error { self?.report(error); self?.saveStatus = "Could not save" }
                    else { self?.saveStatus = "Saved locally" }
                }
            }
        }
    }

    @discardableResult func saveNow() -> Bool {
        saveTask?.cancel()
        guard writable, let disk else { return false }
        do { try disk.save(library, settings: settings); saveStatus = "Saved locally"; return true }
        catch { report(error); saveStatus = "Could not save"; return false }
    }
    func report(_ error: Error) { errorMessage = error.localizedDescription }
    func addSubject(name: String, color: String = "indigo", symbol: String = "book.closed") -> Subject {
        let subject = Subject(name: name.trimmingCharacters(in: .whitespacesAndNewlines), color: color, symbol: symbol)
        library.subjects.append(subject); return subject
    }
    func updateStudySet(_ set: StudySet) {
        if let i = library.studySets.firstIndex(where: { $0.id == set.id }) { library.studySets[i] = set }
        else { library.studySets.append(set) }
    }
    func updateNote(_ note: Note) {
        if let i = library.notes.firstIndex(where: { $0.id == note.id }) { library.notes[i] = note }
        else { library.notes.append(note) }
    }
    func updateAssignment(_ assignment: Assignment) {
        if let i = library.assignments.firstIndex(where: { $0.id == assignment.id }) { library.assignments[i] = assignment }
        else { library.assignments.append(assignment) }
    }
    func deleteMaterial(_ material: Material) {
        guard writable, isSafeManagedFilename(material.storedFilename) else { errorMessage = "This material cannot be deleted safely. Your local files have been preserved."; return }
        let previous = library
        library.materials.removeAll { $0.id == material.id }
        for i in library.assignments.indices { library.assignments[i].materialIDs.removeAll { $0 == material.id } }
        pruneSources { $0.materialID == material.id }
        guard saveNow() else { library = previous; saveTask?.cancel(); saveStatus = "Could not save — deletion cancelled"; return }
        do { let url = materialURL(material); if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
        catch { report(error) }
    }
    func deleteNote(_ id: UUID) {
        library.notes.removeAll { $0.id == id }; pruneSources { $0.noteID == id }
    }
    func deleteAssignment(_ id: UUID) {
        library.assignments.removeAll { $0.id == id }; pruneSources { $0.assignmentID == id }
    }
    func deleteSubject(_ id: UUID) {
        guard writable else { return }
        let materials = library.materials.filter { $0.subjectID == id }
        guard materials.allSatisfy({ isSafeManagedFilename($0.storedFilename) }) else { errorMessage = "This subject contains an invalid managed filename. Your local files have been preserved."; return }
        let previous = library
        let materialIDs = Set(materials.map(\.id))
        let noteIDs = Set(library.notes.filter { $0.subjectID == id }.map(\.id))
        let assignmentIDs = Set(library.assignments.filter { $0.subjectID == id }.map(\.id))
        library.materials.removeAll { $0.subjectID == id }
        library.notes.removeAll { $0.subjectID == id }
        library.assignments.removeAll { $0.subjectID == id }
        for i in library.assignments.indices { library.assignments[i].materialIDs.removeAll { materialIDs.contains($0) } }
        pruneSources { $0.materialID.map(materialIDs.contains) == true || $0.noteID.map(noteIDs.contains) == true || $0.assignmentID.map(assignmentIDs.contains) == true }
        library.conversations.removeAll { $0.subjectID == id }
        library.studySets.removeAll { $0.subjectID == id }
        library.subjects.removeAll { $0.id == id }
        guard saveNow() else { library = previous; saveTask?.cancel(); saveStatus = "Could not save — deletion cancelled"; return }
        route = .today
        for material in materials {
            do { let url = materialURL(material); if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
            catch { report(error) }
        }
    }
    private func pruneSources(where predicate: (SourceReference) -> Bool) {
        for i in library.conversations.indices {
            for j in library.conversations[i].messages.indices { library.conversations[i].messages[j].sources.removeAll(where: predicate) }
        }
    }
    func materialURL(_ material: Material) -> URL {
        guard isSafeManagedFilename(material.storedFilename) else { return materialsURL.appendingPathComponent("invalid-managed-file") }
        return materialsURL.appendingPathComponent(material.storedFilename)
    }
    private func isSafeManagedFilename(_ filename: String) -> Bool {
        !filename.isEmpty && filename != "." && filename != ".." && (filename as NSString).lastPathComponent == filename && !filename.contains("/") && !filename.contains("\\")
    }
    func importFiles(_ urls: [URL], subjectID: UUID) {
        guard writable else { return }
        guard importTask == nil else { errorMessage = "An import is already running. Wait for it to finish or cancel it."; return }
        importTask = Task {
            defer { importStatus = nil; importTask = nil }
            var failures: [String] = []
            for (index, url) in urls.enumerated() {
                guard !Task.isCancelled else { break }
                importStatus = "Importing \(index + 1) of \(urls.count): \(url.lastPathComponent)"
                do {
                    let material = try await DocumentImporter.importFile(at: url, subjectID: subjectID, into: materialsURL)
                    guard library.subjects.contains(where: { $0.id == subjectID }) else {
                        try? FileManager.default.removeItem(at: materialURL(material)); continue
                    }
                    library.materials.append(material)
                } catch is CancellationError { break }
                catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
            saveNow()
        }
    }
    func cancelImport() { importTask?.cancel() }
    func tutor(subjectID: UUID?, materialIDs: Set<UUID> = [], noteIDs: Set<UUID> = [], assignmentID: UUID? = nil, prompt: String = "") {
        tutorLaunch = TutorLaunch(subjectID: subjectID, materialIDs: materialIDs, noteIDs: noteIDs, assignmentID: assignmentID, prompt: prompt)
        route = .tutor
    }
    func openSource(_ source: SourceReference) {
        guard sourceIndex?.resolves(source) == true else { errorMessage = "This source was changed or deleted, or its index is updating. Ask again using the current material."; return }
        if let id = source.materialID { openedMaterial = MaterialLocation(id: id, page: source.page ?? 1) }
        else if let id = source.noteID, let note = library.notes.first(where: { $0.id == id }) { openNote(note) }
        else if let id = source.assignmentID, let assignment = library.assignments.first(where: { $0.id == id }) { openAssignment(assignment) }
    }
    func openNote(_ note: Note) {
        openedMaterial = nil
        openedNoteID = note.id
        route = .subject(note.subjectID)
    }
    func openAssignment(_ assignment: Assignment) {
        openedMaterial = nil
        openedAssignmentID = assignment.id
        route = .subject(assignment.subjectID)
    }
    var subjectIsSelected: Bool { if case .subject = route { return true }; return false }

    func aiCredentials() throws -> String {
        guard !settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError("Choose a model in Clevylo Settings → AI Provider first.") }
        if settings.provider == .openRouter {
            guard settings.cloudConsent else { throw AppError("Before sending content to OpenRouter, review and enable cloud sharing in Settings → AI Provider.") }
            guard let key = try KeychainStore().load(), !key.isEmpty else { throw AppError("Add your OpenRouter API key in Clevylo Settings → AI Provider.") }
            return key
        }
        return ""
    }
    func aiComplete(request: AIRequest) async throws -> String {
        let key = try aiCredentials()
        return try await ProviderFactory.make(settings.provider).complete(request: request, apiKey: key, model: settings.model)
    }
}

enum AppRoute: Hashable { case today, subjects, subject(UUID), study, tutor }
struct TutorLaunch: Identifiable {
    var id = UUID()
    var subjectID: UUID?
    var materialIDs: Set<UUID>
    var noteIDs: Set<UUID>
    var assignmentID: UUID?
    var prompt: String
}
struct MaterialLocation: Identifiable { var id: UUID; var page: Int = 1 }

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct SubjectView: View {
    @EnvironmentObject var store: LibraryStore
    var subjectID: UUID
    @State private var section = "Materials"
    @State private var search = ""
    @State private var noteID: UUID?
    @State private var assignment: Assignment?
    @State private var deleteMaterial: Material?
    @State private var deleteNote: Note?
    @State private var isTargeted = false
    private var subject: Subject? { store.library.subjects.first { $0.id == subjectID } }
    private var materials: [Material] { store.library.materials.filter { $0.subjectID == subjectID && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.pages.contains { $0.text.localizedCaseInsensitiveContains(search) }) } }
    private var notes: [Note] { store.library.notes.filter { $0.subjectID == subjectID && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search)) }.sorted { $0.updatedAt > $1.updatedAt } }
    private var assignments: [Assignment] { store.library.assignments.filter { $0.subjectID == subjectID && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.instructions.localizedCaseInsensitiveContains(search)) }.sorted { $0.dueDate < $1.dueDate } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) { Text(subject?.name ?? "Subject").font(.largeTitle.weight(.semibold)); Text("A home for your materials, ideas, and next steps.").foregroundStyle(.secondary) }
                Spacer()
                Button("Ask Tutor") { store.tutor(subjectID: subjectID) }
            }.padding(28)
            Picker("Subject section", selection: $section) { Text("Materials").tag("Materials"); Text("Notes").tag("Notes"); Text("Assignments").tag("Assignments"); Text("Study sets").tag("Study") }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 28).padding(.bottom, 20).accessibilityIdentifier("subjectSection")
            Divider()
            if let status = store.importStatus {
                HStack { ProgressView().controlSize(.small); Text(status).font(.callout); Spacer(); Button("Cancel Import") { store.cancelImport() } }.padding(12)
            }
            switch section {
            case "Materials": materialList
            case "Notes": noteList
            case "Study": StudyView(subjectID: subjectID)
            default: assignmentList
            }
        }
        .navigationTitle(subject?.name ?? "Subject")
        .searchable(text: $search, prompt: "Search this subject")
        .toolbar {
            if section == "Materials" { Button(action: importMaterials) { Label("Import", systemImage: "square.and.arrow.down") }.help("Import PDF, text, Markdown, or images").disabled(store.importStatus != nil) }
            else if section == "Notes" { Button(action: newNote) { Label("New Note", systemImage: "square.and.pencil") } }
            else if section == "Assignments" { Button { assignment = Assignment(subjectID: subjectID, title: "") } label: { Label("Add Assignment", systemImage: "plus") } }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = await droppedURL(provider) { urls.append(url) }
                }
                store.importFiles(urls, subjectID: subjectID)
            }
            return true
        }
        .overlay { if isTargeted { RoundedRectangle(cornerRadius: 8).stroke(.indigo, lineWidth: 3).padding(8).allowsHitTesting(false) } }
        .sheet(item: $assignment) { AssignmentEditor(assignment: $0) }
        .confirmationDialog("Delete \(deleteMaterial?.name ?? "material") from this Mac?", isPresented: Binding(get: { deleteMaterial != nil }, set: { if !$0 { deleteMaterial = nil } }), titleVisibility: .visible) {
            Button("Delete Material", role: .destructive) { if let material = deleteMaterial { store.deleteMaterial(material) }; deleteMaterial = nil }
        }
        .confirmationDialog("Delete this note?", isPresented: Binding(get: { deleteNote != nil }, set: { if !$0 { deleteNote = nil } }), titleVisibility: .visible) {
            Button("Delete Note", role: .destructive) { if let note = deleteNote { store.deleteNote(note.id); if noteID == note.id { noteID = nil } }; deleteNote = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newNote)) { _ in newNote() }
        .onReceive(NotificationCenter.default.publisher(for: .importMaterial)) { _ in importMaterials() }
        .onAppear { openRequestedItem() }
        .onChange(of: store.openedNoteID) { _, _ in openRequestedItem() }
        .onChange(of: store.openedAssignmentID) { _, _ in openRequestedItem() }
    }

    private var materialList: some View {
        Group {
            if materials.isEmpty {
                EmptyState(symbol: "doc.badge.plus", title: search.isEmpty ? "Bring your class materials" : "No matching materials", detail: "Import or drop PDF, text, Markdown, and image files. Clevylo keeps its own local copies.", action: "Import Materials…", perform: importMaterials)
            } else {
                List(materials) { material in
                    HStack(spacing: 14) {
                        Image(systemName: material.kind == "pdf" ? "doc.richtext" : "doc.text").font(.title2).foregroundStyle(.secondary)
                        Button { store.openedMaterial = MaterialLocation(id: material.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(material.name).fontWeight(.medium)
                                Text("\(material.pages.count) page\(material.pages.count == 1 ? "" : "s") · \(material.importedAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                                if material.warning != nil || material.pages.contains(where: { $0.warning != nil }) { Label("Review extracted text", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Open \(material.name)")
                        Button { store.tutor(subjectID: subjectID, materialIDs: [material.id]) } label: { Image(systemName: "bubble.left") }.help("Ask about this material").accessibilityLabel("Ask about \(material.name)")
                    }.padding(.vertical, 10).accessibilityElement(children: .contain)
                        .contentShape(Rectangle()).onTapGesture(count: 2) { store.openedMaterial = MaterialLocation(id: material.id) }
                        .contextMenu {
                            Button("Open") { store.openedMaterial = MaterialLocation(id: material.id) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.materialURL(material)]) }
                            Button("Delete…", role: .destructive) { deleteMaterial = material }
                        }
                }.listStyle(.inset)
            }
        }
    }
    private var noteList: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $noteID) {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 5) { Text(note.title).fontWeight(.medium); Text(note.text.isEmpty ? "Empty note" : String(note.text.prefix(75))).font(.caption).foregroundStyle(.secondary).lineLimit(2) }.padding(.vertical, 6).tag(note.id)
                            .contextMenu { Button("Delete Note…", role: .destructive) { deleteNote = note } }
                    }
                }
                Button(action: newNote) { Label("New Note", systemImage: "plus") }.padding(12)
            }.frame(minWidth: 180, idealWidth: 230, maxWidth: 300)
            if let id = noteID, store.library.notes.contains(where: { $0.id == id }) { NoteEditor(noteID: id).id(id).frame(minWidth: 300) }
            else { EmptyState(symbol: "note.text", title: "Space to think", detail: "Create a note or select one to continue writing.", action: "New Note", perform: newNote) }
        }
    }
    private var assignmentList: some View {
        Group {
            if assignments.isEmpty { EmptyState(symbol: "checklist", title: search.isEmpty ? "Know what’s next" : "No matching assignments", detail: "Add an assignment with a deadline and relevant materials.", action: "Add Assignment") { assignment = Assignment(subjectID: subjectID, title: "") } }
            else {
                List(assignments) { item in
                    HStack(spacing: 12) {
                        Button { var updated = item; updated.isComplete.toggle(); updated.updatedAt = Date(); store.updateAssignment(updated) } label: { Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(item.isComplete ? .green : .secondary) }.buttonStyle(.plain).accessibilityLabel(item.isComplete ? "Mark \(item.title) incomplete" : "Complete \(item.title)")
                        Button { assignment = item } label: {
                            VStack(alignment: .leading, spacing: 5) { Text(item.title).strikethrough(item.isComplete).fontWeight(.medium); Text(item.instructions).font(.caption).foregroundStyle(.secondary).lineLimit(2) }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        Text(item.dueDate.formatted).font(.callout).foregroundStyle(!item.isComplete && item.dueDate < .today ? .red : .secondary)
                    }.padding(.vertical, 9)
                }.listStyle(.inset)
            }
        }
    }
    private func newNote() {
        search = ""; section = "Notes"
        let note = Note(subjectID: subjectID); store.updateNote(note); noteID = note.id
    }
    private func openRequestedItem() {
        if let id = store.openedNoteID, store.library.notes.contains(where: { $0.id == id && $0.subjectID == subjectID }) { section = "Notes"; noteID = id; search = ""; store.openedNoteID = nil }
        if let id = store.openedAssignmentID, let item = store.library.assignments.first(where: { $0.id == id && $0.subjectID == subjectID }) { section = "Assignments"; assignment = item; search = ""; store.openedAssignmentID = nil }
    }
    private func importMaterials() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf, .plainText, .text, .image, UTType(filenameExtension: "md") ?? .text]
        panel.message = "Import a managed copy into \(subject?.name ?? "this subject")."
        panel.begin { response in if response == .OK { Task { @MainActor in store.importFiles(panel.urls, subjectID: subjectID) } } }
    }
    private func droppedURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                continuation.resume(returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
            }
        }
    }
}

struct NoteEditor: View {
    @EnvironmentObject var store: LibraryStore
    var noteID: UUID
    private var note: Note? { store.library.notes.first { $0.id == noteID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Note title", text: binding(\.title)).font(.title2.weight(.semibold)).textFieldStyle(.plain).accessibilityIdentifier("noteTitle")
            HStack { Text("Autosaved on this Mac").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Ask Tutor") { if let note { store.tutor(subjectID: note.subjectID, noteIDs: [note.id]) } } }
            Divider()
            TextEditor(text: binding(\.text)).font(.body).scrollContentBackground(.hidden).accessibilityLabel("Note body").accessibilityIdentifier("noteBody")
        }.padding(22)
    }
    private func binding(_ keyPath: WritableKeyPath<Note, String>) -> Binding<String> {
        Binding(get: { note?[keyPath: keyPath] ?? "" }, set: { value in guard var note else { return }; note[keyPath: keyPath] = value; note.updatedAt = Date(); store.updateNote(note) })
    }
}

struct AssignmentEditor: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State var assignment: Assignment
    @State private var confirmDelete = false
    private var exists: Bool { store.library.assignments.contains { $0.id == assignment.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(exists ? "Assignment" : "New assignment").font(.title2.weight(.semibold))
            TextField("Assignment title", text: $assignment.title).textFieldStyle(.roundedBorder).accessibilityIdentifier("assignmentTitle")
            Text("Instructions or your draft").font(.headline)
            TextEditor(text: $assignment.instructions).font(.body).frame(height: 110).border(.quaternary).accessibilityLabel("Assignment instructions")
            HStack {
                DatePicker("Due date", selection: Binding(get: { assignment.dueDate.date() }, set: { assignment.dueDate = LocalDay($0) }), displayedComponents: .date).accessibilityIdentifier("assignmentDueDate")
                Spacer(); Toggle("Completed", isOn: $assignment.isComplete)
            }
            let materials = store.library.materials.filter { $0.subjectID == assignment.subjectID }
            if !materials.isEmpty {
                Text("Attached materials").font(.headline)
                ScrollView { VStack(alignment: .leading) { ForEach(materials) { material in
                    Toggle(material.name, isOn: Binding(get: { assignment.materialIDs.contains(material.id) }, set: { value in if value { assignment.materialIDs.append(material.id) } else { assignment.materialIDs.removeAll { $0 == material.id } } }))
                } } }.frame(maxHeight: 110)
            }
            if exists {
                HStack {
                    Menu("Work with Tutor") {
                        Button("Break into steps") { launchTutor("Break this assignment into manageable steps. Explain the requirements.") }
                        Button("Explain requirements") { launchTutor("Explain what this assignment asks me to do.") }
                        Button("Review my draft") { launchTutor("Review the draft in this assignment. Give constructive feedback and explain improvements.") }
                    }
                    Spacer(); Button("Delete…", role: .destructive) { confirmDelete = true }
                }
            }
            Divider()
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save Assignment") { save(); dismiss() }.keyboardShortcut(.defaultAction).disabled(assignment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveAssignment") }
        }.padding(24).frame(width: 540)
        .confirmationDialog("Delete this assignment?", isPresented: $confirmDelete, titleVisibility: .visible) { Button("Delete Assignment", role: .destructive) { store.deleteAssignment(assignment.id); dismiss() } }
    }
    private func save() { assignment.title = assignment.title.trimmingCharacters(in: .whitespacesAndNewlines); assignment.updatedAt = Date(); store.updateAssignment(assignment); store.saveNow() }
    private func launchTutor(_ prompt: String) { save(); dismiss(); store.tutor(subjectID: assignment.subjectID, materialIDs: Set(assignment.materialIDs), assignmentID: assignment.id, prompt: prompt) }
}

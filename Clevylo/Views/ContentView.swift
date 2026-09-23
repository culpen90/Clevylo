import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var newSubject = false
    @State private var editingSubject: Subject?
    @State private var deletingSubject: Subject?
    var body: some View {
        NavigationSplitView {
            List(selection: Binding<AppRoute?>(get: { store.route }, set: { if let value = $0 { store.route = value } })) {
                Section {
                    Label("Today", systemImage: "sun.max").tag(AppRoute.today)
                    Label("Subjects", systemImage: "books.vertical").tag(AppRoute.subjects)
                    Label("Study", systemImage: "rectangle.on.rectangle").tag(AppRoute.study)
                    Label("Tutor", systemImage: "bubble.left.and.text.bubble.right").tag(AppRoute.tutor)
                }
                Section("Your subjects") {
                    ForEach(store.library.subjects) { subject in
                        Label { Text(subject.name) } icon: { Image(systemName: subject.symbol).foregroundStyle(subject.tint) }
                            .tag(AppRoute.subject(subject.id))
                            .contextMenu {
                                Button("Edit Subject…") { editingSubject = subject }
                                Button("Delete Subject…", role: .destructive) { deletingSubject = subject }
                            }
                    }
                    Button { newSubject = true } label: { Label("Add Subject", systemImage: "plus") }.buttonStyle(.plain)
                        .foregroundStyle(.secondary).accessibilityIdentifier("addSubject")
                }
            }.listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clevylo").font(.headline)
                        Text("Make it click.").font(.caption).foregroundStyle(.secondary)
                        HStack { Text(store.saveStatus).font(.caption2).foregroundStyle(.secondary) }
                            .accessibilityElement(children: .ignore).accessibilityLabel(store.saveStatus).accessibilityIdentifier("saveStatus")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
        } detail: {
            Group {
                switch store.route {
                case .today: TodayView(onAddSubject: { newSubject = true })
                case .subjects: SubjectsView(onAdd: { newSubject = true }, onEdit: { editingSubject = $0 })
                case .subject(let id): SubjectView(subjectID: id).id(id)
                case .study: StudyView()
                case .tutor: TutorView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(.indigo)
        .disabled(store.isReadOnly)
        .overlay { if store.isReadOnly { VStack(spacing: 12) { Text("Your library needs attention").font(.title2); Text("Existing files are preserved. Restore a backup or inspect the library folder, then reopen Clevylo.").multilineTextAlignment(.center); Button("Show Library Folder") { NSWorkspace.shared.open(store.rootURL) } }.padding(30).frame(width: 460).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .sheet(isPresented: $newSubject) { SubjectEditor(subject: nil) }
        .sheet(item: $editingSubject) { SubjectEditor(subject: $0) }
        .sheet(item: $store.openedMaterial) { location in
            if let material = store.library.materials.first(where: { $0.id == location.id }) {
                MaterialWorkspace(materialID: material.id, initialPage: location.page).frame(minWidth: 900, minHeight: 650)
            }
        }
        .alert("Clevylo", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .confirmationDialog("Delete \(deletingSubject?.name ?? "subject") and all of its local materials, notes, assignments, conversations, and study sets?", isPresented: Binding(get: { deletingSubject != nil }, set: { if !$0 { deletingSubject = nil } }), titleVisibility: .visible) {
            Button("Delete Subject", role: .destructive) { if let id = deletingSubject?.id { store.deleteSubject(id) }; deletingSubject = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newSubject)) { _ in newSubject = true }
        .onReceive(NotificationCenter.default.publisher(for: .newNote)) { _ in
            if case .subject = store.route { return }
            if let subject = store.library.subjects.first { store.route = .subject(subject.id); DispatchQueue.main.async { NotificationCenter.default.post(name: .newNote, object: nil) } }
            else { newSubject = true }
        }
    }
}

struct TodayView: View {
    @EnvironmentObject var store: LibraryStore
    var onAddSubject: () -> Void
    private var active: [Assignment] { store.library.assignments.filter { !$0.isComplete }.sorted { $0.dueDate < $1.dueDate } }
    private var due: Int { store.library.studySets.flatMap(\.cards).filter { $0.dueDate <= .today }.count }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.subheadline).foregroundStyle(.secondary)
                    Text("Today").font(.largeTitle.weight(.semibold))
                    Text(store.library.subjects.isEmpty ? "A little clarity goes a long way." : "Your next steps, drawn from your own work.").foregroundStyle(.secondary)
                }
                if store.library.subjects.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Make room for what you’re learning", systemImage: "books.vertical").font(.title2)
                        Text("Create a subject, bring in your class materials, and turn difficult ideas into something you understand.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Create Your First Subject", action: onAddSubject).buttonStyle(.borderedProminent).controlSize(.large)
                        Divider()
                        Label("Your library stays on this Mac", systemImage: "internaldrive").font(.subheadline.weight(.medium))
                        Text("Notes, materials, homework, and saved study sets work offline. Connect a local Ollama model or OpenRouter when you’re ready for tutoring.").font(.callout).foregroundStyle(.secondary)
                        SettingsLink { Text("Set Up AI Provider…") }
                    }.padding(24).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("Assignments").font(.title2.weight(.semibold))
                    if active.isEmpty { Text("No upcoming assignments. Add homework inside a subject.").foregroundStyle(.secondary) }
                    ForEach(active.prefix(10)) { assignment in
                        HStack(spacing: 12) {
                            Button { var a = assignment; a.isComplete = true; a.updatedAt = Date(); store.updateAssignment(a) } label: { Image(systemName: "circle").font(.title3) }.buttonStyle(.plain).accessibilityLabel("Complete \(assignment.title)")
                            Button { store.openAssignment(assignment) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(assignment.title).fontWeight(.medium)
                                    Text(store.library.subjects.first { $0.id == assignment.subjectID }?.name ?? "Subject").font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                            Spacer()
                            Text(assignment.dueDate == .today ? "Today" : assignment.dueDate.formatted).font(.callout).foregroundStyle(assignment.dueDate < .today ? .red : .secondary)
                            if assignment.dueDate < .today { Text("Overdue").font(.caption).foregroundStyle(.red) }
                        }.padding(.vertical, 6)
                        Divider()
                    }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ready for review").font(.title2.weight(.semibold))
                        Text(due == 0 ? "No flashcards due. Create a study set from a topic or your materials." : "\(due) flashcard\(due == 1 ? "" : "s") due today.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Study") { store.route = .study }
                }
                if !store.library.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent notes").font(.title2.weight(.semibold))
                        ForEach(store.library.notes.sorted { $0.updatedAt > $1.updatedAt }.prefix(5)) { note in
                            Button { store.openNote(note) } label: {
                                HStack { Label(note.title, systemImage: "note.text"); Spacer(); Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary) }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(32).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }.navigationTitle("Today")
    }
}

struct SubjectsView: View {
    @EnvironmentObject var store: LibraryStore
    var onAdd: () -> Void
    var onEdit: (Subject) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Subjects", subtitle: "Keep the right materials and ideas together.")
            if store.library.subjects.isEmpty { EmptyState(symbol: "books.vertical", title: "Start with one subject", detail: "Give your classes a home, then add notes and materials.", action: "Add Subject", perform: onAdd) }
            else {
                List(store.library.subjects) { subject in
                    HStack(spacing: 16) {
                        Image(systemName: subject.symbol).font(.title2).foregroundStyle(subject.tint).frame(width: 32)
                        Button { store.route = .subject(subject.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(subject.name).font(.headline)
                                Text("\(store.library.materials.filter { $0.subjectID == subject.id }.count) materials · \(store.library.notes.filter { $0.subjectID == subject.id }.count) notes").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        Button { onEdit(subject) } label: { Image(systemName: "pencil") }.accessibilityLabel("Edit \(subject.name)")
                    }.padding(.vertical, 12)
                }.listStyle(.inset)
            }
        }.navigationTitle("Subjects").toolbar { Button(action: onAdd) { Label("Add Subject", systemImage: "plus") } }
    }
}

struct SubjectEditor: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var subject: Subject?
    @State private var name = ""
    @State private var color = "indigo"
    @State private var symbol = "book.closed"
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(subject == nil ? "New subject" : "Edit subject").font(.title2.weight(.semibold))
            TextField("Subject name", text: $name).textFieldStyle(.roundedBorder).focused($focused).accessibilityIdentifier("subjectName")
            Picker("Color", selection: $color) { ForEach(["indigo", "teal", "orange", "pink", "purple", "blue"], id: \.self) { Text($0.capitalized).tag($0) } }
            Picker("Symbol", selection: $symbol) {
                Label("Book", systemImage: "book.closed").tag("book.closed")
                Label("Science", systemImage: "atom").tag("atom")
                Label("Math", systemImage: "function").tag("function")
                Label("Language", systemImage: "text.book.closed").tag("text.book.closed")
                Label("History", systemImage: "globe").tag("globe")
                Label("Art", systemImage: "paintpalette").tag("paintpalette")
            }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(subject == nil ? "Create Subject" : "Save") {
                    if var subject, let i = store.library.subjects.firstIndex(where: { $0.id == subject.id }) {
                        subject.name = name.trimmingCharacters(in: .whitespacesAndNewlines); subject.color = color; subject.symbol = symbol; store.library.subjects[i] = subject
                    } else {
                        let new = store.addSubject(name: name, color: color, symbol: symbol); store.route = .subject(new.id)
                    }
                    store.saveNow(); dismiss()
                }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveSubject")
            }
        }.padding(24).frame(width: 390).onAppear { name = subject?.name ?? ""; color = subject?.color ?? "indigo"; symbol = subject?.symbol ?? "book.closed"; focused = true }
    }
}

extension Subject {
    var tint: Color { switch color { case "teal": return .teal; case "orange": return .orange; case "pink": return .pink; case "purple": return .purple; case "blue": return .blue; default: return .indigo } }
}
struct PageHeader: View {
    var title: String; var subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.largeTitle.weight(.semibold)); Text(subtitle).foregroundStyle(.secondary) }.padding(28).frame(maxWidth: .infinity, alignment: .leading) }
}
struct EmptyState: View {
    var symbol: String; var title: String; var detail: String; var action: String? = nil; var perform: (() -> Void)? = nil
    var body: some View { VStack(spacing: 14) { Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(.secondary); Text(title).font(.title2.weight(.medium)); Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420); if let action, let perform { Button(action, action: perform).buttonStyle(.borderedProminent) } }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity) }
}

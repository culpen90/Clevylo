import SwiftUI
import PDFKit
import AppKit

struct MaterialWorkspace: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var materialID: UUID
    var initialPage: Int = 1
    @State private var page = 1
    @State private var extracted = false
    @State private var showTutor = true
    private var material: Material? { store.library.materials.first { $0.id == materialID } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) { Text(material?.name ?? "Material unavailable").font(.headline); Text(store.library.subjects.first { $0.id == material?.subjectID }?.name ?? "").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Toggle("Extracted Text", isOn: $extracted).toggleStyle(.button)
                Toggle("Tutor", isOn: $showTutor).toggleStyle(.button)
                Button("Done") { store.saveNow(); dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider()
            if let material {
                HSplitView {
                    VStack(spacing: 0) {
                        HStack {
                            Button { page = max(1, page - 1) } label: { Image(systemName: "chevron.left") }.disabled(page <= 1).accessibilityLabel("Previous page")
                            Text("Page \(page) of \(max(1, material.pages.count))").font(.callout).monospacedDigit()
                            Button { page = min(material.pages.count, page + 1) } label: { Image(systemName: "chevron.right") }.disabled(page >= material.pages.count).accessibilityLabel("Next page")
                            Spacer()
                        }.padding(12)
                        if let warning = currentPage?.warning ?? material.warning { Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).padding(12).frame(maxWidth: .infinity, alignment: .leading) }
                        if extracted {
                            Text("Inspect and correct recognition errors, especially formulas. Changes autosave and update retrieval.").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                            TextEditor(text: Binding(get: { currentPage?.text ?? "" }, set: updateText)).font(.system(.body, design: .monospaced)).padding(10).accessibilityLabel("Extracted page text")
                        } else if material.kind == "pdf" {
                            PDFDocumentView(url: store.materialURL(material), page: $page)
                        } else if ["image", "png", "jpg", "jpeg", "heic", "tiff", "gif", "webp"].contains(material.kind), let image = NSImage(contentsOf: store.materialURL(material)) {
                            ScrollView([.horizontal, .vertical]) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 1000, maxHeight: 1100).padding() }
                        } else {
                            ScrollView { Text(currentPage?.text ?? "No readable text. Open Extracted Text to add a transcription.").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(22) }
                        }
                    }.frame(minWidth: 360, idealWidth: 520)
                    if showTutor { TutorPanel(initialSubjectID: material.subjectID, initialMaterialIDs: [material.id], compact: true).frame(minWidth: 330, idealWidth: 390) }
                }
            } else { EmptyState(symbol: "doc.questionmark", title: "Material unavailable", detail: "This material may have been deleted.") }
        }.onAppear { page = initialPage }.onChange(of: initialPage) { _, newPage in page = newPage }
    }
    private var currentPage: MaterialPage? { material?.pages.first { $0.number == page } }
    private func updateText(_ text: String) {
        guard let i = store.library.materials.firstIndex(where: { $0.id == materialID }), let j = store.library.materials[i].pages.firstIndex(where: { $0.number == page }) else { return }
        store.library.materials[i].pages[j].text = text
        store.library.materials[i].pages[j].warning = "Manually edited text. Verify formulas against the original."
    }
}

struct PDFDocumentView: NSViewRepresentable {
    var url: URL
    @Binding var page: Int
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.document = PDFDocument(url: url)
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak view] _ in
            guard let view, let current = view.currentPage, let document = view.document else { return }
            let number = document.index(for: current) + 1
            DispatchQueue.main.async { context.coordinator.parent.page = number }
        }
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
        if let document = view.document, let target = document.page(at: page - 1), target != view.currentPage { view.go(to: target) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator {
        var parent: PDFDocumentView; var observer: NSObjectProtocol?
        init(_ parent: PDFDocumentView) { self.parent = parent }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

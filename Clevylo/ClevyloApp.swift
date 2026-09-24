import SwiftUI
import AppKit

@main
@MainActor
struct ClevyloApp: App {
    @NSApplicationDelegateAdaptor(ClevyloApplicationDelegate.self) private var applicationDelegate
    @StateObject private var store: LibraryStore
    @StateObject private var updater: AppUpdater
    @AppStorage("appearance") private var appearance = "system"

    init() {
        let library = LibraryStore()
        _store = StateObject(wrappedValue: library)
        _updater = StateObject(wrappedValue: AppUpdater())
    }

    var body: some Scene {
        Window("Clevylo", id: "main") {
            ContentView().environmentObject(store)
                .frame(minWidth: 880, minHeight: 580)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .onAppear { applicationDelegate.beforeTermination = { store.isReadOnly || store.saveNow() } }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.saveNow() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in store.saveNow() }
        }
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                    .accessibilityIdentifier("checkForUpdatesMenuItem")
            }
            CommandGroup(replacing: .newItem) {
                Button("New Subject…") { NotificationCenter.default.post(name: .newSubject, object: nil) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Note") { NotificationCenter.default.post(name: .newNote, object: nil) }.keyboardShortcut("n")
                Button("Import Materials…") { NotificationCenter.default.post(name: .importMaterial, object: nil) }.keyboardShortcut("i", modifiers: [.command, .shift]).disabled(!store.subjectIsSelected)
            }
            CommandMenu("Navigate") {
                Button("Today") { store.route = .today }.keyboardShortcut("1")
                Button("Subjects") { store.route = .subjects }.keyboardShortcut("2")
                Button("Study") { store.route = .study }.keyboardShortcut("3")
                Button("Tutor") { store.route = .tutor }.keyboardShortcut("4")
            }
        }
        Settings { ProviderSettingsView().environmentObject(store).environmentObject(updater) }
    }
}

extension Notification.Name {
    static let newSubject = Notification.Name("ClevyloNewSubject")
    static let newNote = Notification.Name("ClevyloNewNote")
    static let importMaterial = Notification.Name("ClevyloImportMaterial")
}

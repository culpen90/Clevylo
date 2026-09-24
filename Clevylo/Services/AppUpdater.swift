import AppKit
import Combine
import Sparkle

/// One updater per application. Sparkle owns checking, download verification,
/// installation, relaunch, and the user's update preferences.
@MainActor
final class AppUpdater: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published private(set) var startupError: String?
    private let controller: SPUStandardUpdaterController
    private var subscriptions = Set<AnyCancellable>()

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    override init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.lastUpdateCheckDate)
            .assign(to: &$lastUpdateCheckDate)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)

        // Unit-test hosts must never schedule network checks or permission UI.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        do { try controller.updater.start() }
        catch { startupError = "Updates are unavailable: \(error.localizedDescription)" }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }
}

/// Sparkle asks NSApplication to terminate before replacing the app. Refusing
/// termination on a failed save protects pending edits during an update as well
/// as when the user quits normally.
@MainActor
final class ClevyloApplicationDelegate: NSObject, NSApplicationDelegate {
    var beforeTermination: (() -> Bool)?
    var showSaveFailure: () -> Void = {
        let alert = NSAlert()
        alert.messageText = "Clevylo couldn’t save your library"
        alert.informativeText = "The app will stay open to protect your changes. Check the library’s location and available disk space, then try again."
        alert.addButton(withTitle: "Keep Clevylo Open")
        alert.alertStyle = .warning
        alert.runModal()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard beforeTermination?() != false else {
            showSaveFailure()
            return .terminateCancel
        }
        return .terminateNow
    }
}

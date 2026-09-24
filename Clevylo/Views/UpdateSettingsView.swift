import SwiftUI

struct UpdateSettingsView: View {
    @EnvironmentObject private var updater: AppUpdater

    private var installedVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        Form {
            Section("Clevylo updates") {
                LabeledContent("Installed version") {
                    Text(installedVersion).textSelection(.enabled)
                        .accessibilityIdentifier("installedVersion")
                }
                Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                    .disabled(updater.startupError != nil)
                    .accessibilityIdentifier("automaticallyCheckForUpdates")
                Text("Clevylo can let you know when a new version is available. You choose when to download and install it.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                    .accessibilityIdentifier("checkForUpdates")
                LabeledContent("Last checked") {
                    if let date = updater.lastUpdateCheckDate {
                        Text(date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                    } else {
                        Text("Not yet checked")
                    }
                }.foregroundStyle(.secondary).accessibilityIdentifier("lastUpdateCheck")
                if let error = updater.startupError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).textSelection(.enabled)
                        .accessibilityIdentifier("updateStartupError")
                }
            }
            Section("Privacy") {
                Text("Update checks and downloads contact GitHub. Your library, documents, conversations, and API key are never included in update requests. No analytics or system profile is sent.")
                    .font(.callout).foregroundStyle(.secondary)
                Link("View release notes", destination: URL(string: "https://github.com/culpen90/Clevylo/releases")!)
            }
        }.formStyle(.grouped)
    }
}

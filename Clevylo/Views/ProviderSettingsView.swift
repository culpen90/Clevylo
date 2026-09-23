import SwiftUI
import AppKit

struct ProviderSettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @AppStorage("appearance") private var appearance = "system"
    @State private var key = ""
    @State private var hasKey = false
    @State private var models: [String] = []
    @State private var status = "Choose a provider and model, then test the connection."
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        TabView {
            Form {
                Section {
                    Picker("Provider", selection: $store.settings.provider) { ForEach(ProviderKind.allCases) { Text($0.title).tag($0) } }.onChange(of: store.settings.provider) { _, _ in task?.cancel(); models = []; store.settings.model = ""; status = "Choose a model for this provider." }
                    if store.settings.provider == .ollama {
                        Text("Connects to Ollama on this Mac at 127.0.0.1:11434. Install and run Ollama, then install a suitable local model yourself. Clevylo never downloads models.").font(.callout).foregroundStyle(.secondary)
                        Link("Ollama setup guide", destination: URL(string: "https://docs.ollama.com/quickstart")!)
                        Text("Cloud-backed Ollama models are blocked. Image understanding and structured output depend on the model you install.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        SecureField(hasKey ? "Key saved in Keychain — enter to replace" : "OpenRouter API key", text: $key).accessibilityIdentifier("apiKey")
                        HStack {
                            Button("Save Key") {
                                do { try KeychainStore().save(key.trimmingCharacters(in: .whitespacesAndNewlines)); key = ""; hasKey = true; status = "API key saved securely in macOS Keychain." }
                                catch { status = error.localizedDescription }
                            }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button("Remove Key", role: .destructive) { do { try KeychainStore().delete(); hasKey = false; status = "API key removed." } catch { status = error.localizedDescription } }.disabled(!hasKey)
                        }
                        Text("OpenRouter requires its own API key and applicable credits or billing. A ChatGPT subscription does not provide OpenRouter API access. Requests may be routed to the model’s provider under OpenRouter’s policies.").font(.callout).foregroundStyle(.secondary)
                        Link("OpenRouter keys and setup", destination: URL(string: "https://openrouter.ai/settings/keys")!)
                        Toggle("Allow selected content to be sent to OpenRouter", isOn: $store.settings.cloudConsent)
                        Text("When you use cloud AI, your question, recent conversation, selected source excerpts, and any attached images are sent to OpenRouter and its model provider. Your whole library is never uploaded. You can revoke this permission here.").font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("AI Provider") }
                Section {
                    TextField("Model ID", text: $store.settings.model).textFieldStyle(.roundedBorder).accessibilityIdentifier("modelID")
                    HStack {
                        Button(store.settings.provider == .ollama ? "Find Installed Models" : "Find Available Models") { discover() }.disabled(busy)
                        if !models.isEmpty {
                            Menu("Choose Model") { ForEach(models.filter { store.settings.model.isEmpty || $0.localizedCaseInsensitiveContains(store.settings.model) }.prefix(150), id: \.self) { model in Button(model) { store.settings.model = model } }; if !store.settings.model.isEmpty { Button("Clear Filter") { store.settings.model = "" } } }
                        }
                    }
                    Text("Enter the exact installed Ollama tag or OpenRouter model ID. Use a model that supports structured output for study generation and vision for images.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Test Connection") { test() }.disabled(busy || store.settings.model.isEmpty)
                        if busy { ProgressView().controlSize(.small); Button("Cancel") { task?.cancel() } }
                    }
                    Text(status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).accessibilityIdentifier("connectionStatus")
                } header: { Text("Model and connection") }
            }.formStyle(.grouped).tabItem { Label("AI Provider", systemImage: "network") }
            Form {
                Picker("Appearance", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                Section("Local library") {
                    Text("Your library, notes, managed files, assignments, conversations, and study history are saved on this Mac. There are no accounts, analytics, or automatic cloud sync.")
                    Text(store.rootURL.path).font(.caption).textSelection(.enabled)
                    Button("Show Library in Finder") { NSWorkspace.shared.open(store.rootURL) }
                    Text("To back up your work, quit Clevylo and copy this entire folder. The API key remains separately in Keychain.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }
        }.padding(12).frame(width: 610, height: 650)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
            .onAppear { do { hasKey = try KeychainStore().load() != nil } catch { status = error.localizedDescription } }
            .onDisappear { task?.cancel(); store.saveNow() }
    }
    private func discover() {
        guard !busy else { return }; busy = true; status = "Looking for models…"
        let kind = store.settings.provider
        task = Task {
            defer { busy = false }
            do {
                let result = try await ProviderFactory.make(kind).models(apiKey: "")
                try Task.checkCancellation(); guard kind == store.settings.provider else { return }
                models = result
                if store.settings.model.isEmpty && kind == .ollama { store.settings.model = result.first ?? "" }
                status = result.isEmpty ? "No local models found. Install a model in Ollama, then try again." : "Found \(result.count) models. Choose one and test the connection."
            } catch { status = Task.isCancelled ? "Model discovery cancelled." : error.localizedDescription }
        }
    }
    private func test() {
        guard !busy else { return }
        do {
            let credential = try store.aiCredentials(); let settings = store.settings; busy = true; status = "Testing \(settings.model)…"
            task = Task {
                defer { busy = false }
                do { status = try await ProviderFactory.make(settings.provider).testConnection(apiKey: credential, model: settings.model) }
                catch { status = Task.isCancelled ? "Connection test cancelled." : error.localizedDescription }
            }
        } catch { status = error.localizedDescription }
    }
}

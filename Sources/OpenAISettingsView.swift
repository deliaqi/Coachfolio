import SwiftUI

struct OpenAISettingsView: View {
    @AppStorage(OpenAIReviewSettings.providerPreferenceKey) private var provider = OpenAIReviewSettings.defaultProvider.rawValue
    @AppStorage(OpenAIReviewSettings.modelPreferenceKey) private var model = OpenAIReviewSettings.defaultModel
    @State private var apiKey = ""
    @State private var hasSavedKey = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Analysis provider") {
                Picker("Review method", selection: $provider) {
                    ForEach(ReviewProvider.allCases) { item in Text(item.rawValue).tag(item.rawValue) }
                }
                Text(provider == ReviewProvider.openAI.rawValue
                     ? "GPT is the default analysis method. It requires an OpenAI API key and sends transcript text to OpenAI after you request a review."
                     : "On-device mode keeps analysis on this Mac. If Apple’s language model is unavailable, it uses the local language-signal scan.")
                    .font(.system(size: 12)).foregroundStyle(StudioColor.muted)
            }
            Section("OpenAI GPT analysis") {
                SecureField("OpenAI API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save API key") { saveKey() }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if hasSavedKey {
                        Button("Remove saved key", role: .destructive) { removeKey() }
                    }
                    Spacer()
                    if hasSavedKey {
                        Label("Key saved in Keychain", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12)).foregroundStyle(StudioColor.forest)
                    }
                }
                Picker("GPT model", selection: $model) {
                    Text("GPT-6 Luna · efficient").tag("gpt-6-luna")
                    Text("GPT-6.1 Sol · balanced").tag("gpt-6.1-sol")
                    Text("GPT-6 Astra · most capable").tag("gpt-6-astra")
                }
                HStack(spacing: 4) {
                    Link("Create an API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    Text("· API usage is billed separately from ChatGPT.")
                }
                .font(.system(size: 12)).foregroundStyle(StudioColor.muted)
            }

            Section("Transcript privacy") {
                Text("When you request a GPT review, Coachfolio sends the transcript text to OpenAI. It does not send the audio file, client record, or session title. The transcript itself may include identifying details.")
                Text("Requests disable response storage. OpenAI says API data is not used to train models by default; standard abuse monitoring may retain customer content for up to 30 days.")
                Link("OpenAI API data controls", destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560, height: 430)
        .onAppear(perform: refreshKeyStatus)
        .alert("OpenAI settings error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .overlay(alignment: .bottomLeading) {
            if let statusMessage {
                Text(statusMessage).font(.system(size: 12)).foregroundStyle(StudioColor.forest)
                    .padding(.leading, 34).padding(.bottom, 9)
            }
        }
    }

    private func refreshKeyStatus() {
        do {
            hasSavedKey = try OpenAIAPIKeyStore.read() != nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveKey() {
        do {
            try OpenAIAPIKeyStore.save(apiKey)
            apiKey = ""
            hasSavedKey = true
            statusMessage = "API key saved securely on this Mac."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeKey() {
        do {
            try OpenAIAPIKeyStore.delete()
            hasSavedKey = false
            statusMessage = "Saved API key removed."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

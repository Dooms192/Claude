import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.reminderEnabled) private var reminderEnabled = false
    @AppStorage(SettingsKey.reminderHour) private var reminderHour = 21
    @AppStorage(SettingsKey.reminderMinute) private var reminderMinute = 0
    @AppStorage(SettingsKey.summaryEngine) private var summaryEngine: AIEngine = .apple
    @AppStorage(SettingsKey.interviewEngine) private var interviewEngine: AIEngine = .claude
    @AppStorage(ProjectPulse.enabledKey) private var projectPulseEnabled = false
    @Environment(\.modelContext) private var context

    @State private var keyField = ""
    @State private var hasKey = AIConfig.claudeKey != nil
    @State private var keyStatus: String?
    @State private var checkingKey = false
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                reminderSection
                projectsSection
                engineSection
                claudeSection
                Section("Your data") {
                    Label("Your recaps, goals, and interview prep are stored only on this iPhone.", systemImage: "lock.iphone")
                    Label("Speech is turned into text on your device.", systemImage: "waveform")
                    Label("When Claude is used, only the text needed for that request is sent to Anthropic.", systemImage: "network")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Sections

    private var reminderSection: some View {
        Section {
            Toggle("Daily reminder", isOn: $reminderEnabled)
                .onChange(of: reminderEnabled) { _, enabled in
                    Task { await updateReminder(enabled: enabled) }
                }
            if reminderEnabled {
                DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
            }
            if notificationsDenied {
                Text("Notifications are off for Recap. Turn them on in the Settings app to get your reminder.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("End-of-day recap")
        } footer: {
            Text("Recap will nudge you to talk through your day. Tap the notification to start recording.")
        }
    }

    private var projectsSection: some View {
        Section {
            Toggle("Weekly project pulse", isOn: $projectPulseEnabled)
                .onChange(of: projectPulseEnabled) { _, enabled in
                    Task { await updatePulse(enabled: enabled) }
                }
        } header: {
            Text("Projects")
        } footer: {
            Text("A Sunday evening summary, like: \"You moved 3 projects forward this week. 'Website redesign' hasn't been mentioned in 2 weeks.\"")
        }
    }

    private var engineSection: some View {
        Section {
            Picker("Daily summaries", selection: $summaryEngine) {
                ForEach(AIEngine.allCases) { Text($0.name).tag($0) }
            }
            Picker("Interview prep", selection: $interviewEngine) {
                ForEach(AIEngine.allCases) { Text($0.name).tag($0) }
            }
            LabeledContent("Apple Intelligence", value: AppleIntelligence.statusText)
        } header: {
            Text("AI")
        } footer: {
            Text("Recommended: Apple Intelligence for daily summaries (free and private) and Claude for interview prep, because it can reason across months of your days. If your choice isn't available, Recap uses the other one.")
        }
    }

    private var claudeSection: some View {
        Section {
            if hasKey {
                LabeledContent("API key", value: "Saved")
                Button {
                    Task { await checkKey() }
                } label: {
                    if checkingKey { ProgressView() } else { Text("Test key") }
                }
                .disabled(checkingKey)
                Button("Remove key", role: .destructive) {
                    KeychainStore.set(nil, for: AIConfig.claudeKeyAccount)
                    hasKey = false
                    keyStatus = nil
                }
            } else {
                SecureField("Paste your API key (sk-ant-…)", text: $keyField)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save key") {
                    KeychainStore.set(keyField, for: AIConfig.claudeKeyAccount)
                    keyField = ""
                    hasKey = AIConfig.claudeKey != nil
                    Task { await checkKey() }
                }
                .disabled(keyField.trimmed.isEmpty)
            }
            if let keyStatus {
                Text(keyStatus).font(.footnote).foregroundStyle(.secondary)
            }
            Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
        } header: {
            Text("Claude")
        } footer: {
            Text("A Claude Pro subscription doesn't cover apps. The API is billed separately, pay as you go. Interview prep usually costs a few cents per request, and you can set a monthly spending limit in the Anthropic console. Your key is stored in the iPhone Keychain.")
        }
    }

    // MARK: - Actions

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: Date()) ?? Date()
        } set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = parts.hour ?? 21
            reminderMinute = parts.minute ?? 0
            Task { await ReminderScheduler.schedule(hour: reminderHour, minute: reminderMinute) }
        }
    }

    private func updateReminder(enabled: Bool) async {
        guard enabled else {
            ReminderScheduler.cancel()
            return
        }
        let allowed = await ReminderScheduler.requestAuthorization()
        notificationsDenied = !allowed
        if allowed {
            await ReminderScheduler.schedule(hour: reminderHour, minute: reminderMinute)
        } else {
            reminderEnabled = false
        }
    }

    private func updatePulse(enabled: Bool) async {
        guard enabled else {
            ProjectPulse.cancel()
            return
        }
        let allowed = await ReminderScheduler.requestAuthorization()
        notificationsDenied = !allowed
        if allowed {
            await ProjectPulse.reschedule(in: context)
        } else {
            projectPulseEnabled = false
        }
    }

    private func checkKey() async {
        guard let key = AIConfig.claudeKey else { return }
        checkingKey = true
        defer { checkingKey = false }
        do {
            try await ClaudeClient(apiKey: key).verifyKey()
            keyStatus = "Key works. Claude is ready."
        } catch {
            keyStatus = error.localizedDescription
        }
    }
}

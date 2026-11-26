import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(SettingsKey.reminderEnabled) private var reminderEnabled = false
    @AppStorage(SettingsKey.reminderHour) private var reminderHour = 21
    @AppStorage(SettingsKey.reminderMinute) private var reminderMinute = 0
    @AppStorage(SettingsKey.summaryEngine) private var summaryEngine: AIEngine = .apple
    @AppStorage(SettingsKey.interviewEngine) private var interviewEngine: AIEngine = .claude
    @AppStorage(ProjectPulse.enabledKey) private var projectPulseEnabled = false
    @AppStorage(CompetencyPulse.enabledKey) private var competencyPulseEnabled = false
    @Environment(\.modelContext) private var context

    @State private var keyField = ""
    @State private var hasKey = AIConfig.claudeKey != nil
    @State private var keyStatus: String?
    @State private var checkingKey = false
    @State private var notificationsDenied = false

    // Backups
    private enum ImporterKind { case folder, backupFile }
    @State private var backups = BackupManager.shared
    @State private var importerKind: ImporterKind = .folder
    @State private var showingImporter = false
    @State private var pendingRestore: BackupFile?
    @State private var restoring = false
    @State private var backupMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                reminderSection
                backupsSection
                projectsSection
                engineSection
                claudeSection
                Section {
                    Button("Show welcome tour") {
                        UserDefaults.standard.set(false, forKey: Onboarding.completedKey)
                    }
                }
                Section("Your data") {
                    Label("Your recaps, goals, and interview prep are stored only on this iPhone.", systemImage: "lock.iphone")
                    Label("Speech is turned into text on your device.", systemImage: "waveform")
                    Label("When Claude is used, only the text needed for that request is sent to Anthropic.", systemImage: "network")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Settings")
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: importerKind == .folder ? [.folder] : [.json]
            ) { result in
                Task { await handleImport(result) }
            }
            .confirmationDialog(
                "Restore this backup?",
                isPresented: .init(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                titleVisibility: .visible,
                presenting: pendingRestore
            ) { file in
                Button("Replace everything", role: .destructive) { Task { await restore(file, mode: .replace) } }
                Button("Merge (add what's missing)") { Task { await restore(file, mode: .merge) } }
                Button("Cancel", role: .cancel) {}
            } message: { file in
                Text("Backup from \(file.createdAt.formatted(date: .long, time: .shortened)): \(file.preview.description). A safety backup of your current data is saved first.")
            }
            .alert("Backups", isPresented: .init(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(backupMessage ?? "")
            }
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

    private var backupsSection: some View {
        Section {
            if let paused = backups.pausedMessage {
                Label(paused, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            LabeledContent("Backup folder", value: backups.folderName ?? "Not set")
            if backups.folderIsInsideApp {
                Text("This folder is inside Recap itself (On My iPhone → Recap). Deleting the app deletes it too. Choose a folder in iCloud Drive instead.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if backups.hasFolder && !backups.folderIsInICloud {
                Text("This folder isn't in iCloud Drive, so it won't follow you to a new phone.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Button(backups.hasFolder ? "Change backup folder" : "Choose backup folder") {
                importerKind = .folder
                showingImporter = true
            }
            if backups.hasFolder {
                LabeledContent(
                    "Last backup",
                    value: backups.lastBackupAt.map { $0.formatted(.relative(presentation: .named)) } ?? "Never"
                )
                Button {
                    Task {
                        if await backups.backupNow() { backupMessage = "Backed up." }
                    }
                } label: {
                    if backups.isBackingUp { ProgressView() } else { Text("Back up now") }
                }
                .disabled(backups.isBackingUp)
                Picker("Keep", selection: Binding(get: { backups.keepCount }, set: { backups.keepCount = $0 })) {
                    ForEach(BackupManager.keepCountOptions, id: \.self) { Text("Last \($0) backups").tag($0) }
                }
            }
            Button {
                importerKind = .backupFile
                showingImporter = true
            } label: {
                if restoring { ProgressView() } else { Text("Restore from backup…") }
            }
            .disabled(restoring)
        } header: {
            Text("Backups")
        } footer: {
            Text("Recommended: choose a folder in iCloud Drive, like iCloud Drive → Recap Backups. Recap saves a backup there automatically after changes, so your recaps survive deleting the app or switching phones. The free iCloud storage is plenty. Your Claude API key is never included in backups.")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) async {
        guard case .success(let url) = result else { return }
        switch importerKind {
        case .folder:
            await backups.chooseFolder(url)
        case .backupFile:
            do {
                pendingRestore = try await backups.readBackup(at: url)
            } catch {
                backupMessage = error.localizedDescription
            }
        }
    }

    private func restore(_ file: BackupFile, mode: RestoreMode) async {
        restoring = true
        defer { restoring = false }
        do {
            try await backups.restore(file, mode: mode)
            backupMessage = mode == .replace ? "Your backup is restored." : "Your backup is merged in."
        } catch {
            backupMessage = "Couldn't restore: \(error.localizedDescription)"
        }
    }

    private var projectsSection: some View {
        Section {
            Toggle("Weekly project pulse", isOn: $projectPulseEnabled)
                .onChange(of: projectPulseEnabled) { _, enabled in
                    Task { await updatePulse(enabled: enabled) }
                }
            Toggle("Weekly competency pulse", isOn: $competencyPulseEnabled)
                .onChange(of: competencyPulseEnabled) { _, enabled in
                    Task { await updateCompetencyPulse(enabled: enabled) }
                }
        } header: {
            Text("Weekly summaries")
        } footer: {
            Text("Sunday evening notifications, like: \"You moved 3 projects forward this week.\" and \"This week you showed Drives results 3 times. You haven't logged Develops talent in a month.\"")
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

    private func updateCompetencyPulse(enabled: Bool) async {
        guard enabled else {
            CompetencyPulse.cancel()
            return
        }
        let allowed = await ReminderScheduler.requestAuthorization()
        notificationsDenied = !allowed
        if allowed {
            await CompetencyPulse.reschedule(in: context)
        } else {
            competencyPulseEnabled = false
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

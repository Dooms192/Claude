import AVFoundation
import Speech
import SwiftUI
import UniformTypeIdentifiers

enum Onboarding {
    /// Set once the tour is finished or skipped, so it never shows again on its own.
    static let completedKey = "hasCompletedOnboarding"
}

/// The welcome tour, shown once on first launch. It explains the app and walks through the
/// optional setup: microphone, daily reminder, AI, and backups. Every step can be skipped.
///
/// It's a full-screen paged layout capped to a readable width, so it looks right folded,
/// unfolded, and on any iPhone.
struct OnboardingView: View {
    var onFinish: (_ startRecording: Bool) -> Void

    private enum Page: Int, CaseIterable {
        case welcome, howItWorks, microphone, reminder, ai, backups, ready
    }

    @State private var page: Page = .welcome

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page != .ready {
                    Button("Skip") { onFinish(false) }
                        .padding()
                }
            }

            TabView(selection: $page) {
                WelcomePage().tag(Page.welcome)
                HowItWorksPage().tag(Page.howItWorks)
                MicrophonePage().tag(Page.microphone)
                ReminderPage().tag(Page.reminder)
                AIPage().tag(Page.ai)
                BackupPage().tag(Page.backups)
                ReadyPage(onFinish: onFinish).tag(Page.ready)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            if page != .ready {
                Button {
                    withAnimation { page = Page(rawValue: page.rawValue + 1) ?? .ready }
                } label: {
                    Text(page == .welcome ? "Get started" : "Next")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: 420)
                .padding()
            }
        }
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
    }
}

// MARK: - Page layout

/// One page: a big symbol, a title, a short explanation, and optional controls, scrollable
/// for large text sizes and capped to a readable width on the unfolded screen.
private struct OnboardingPage<Content: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: systemImage)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Color.accentColor.gradient)
                    .padding(.top, 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                content
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct FeatureRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(minWidth: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct DoneLabel: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.headline)
            .foregroundStyle(.green)
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    var body: some View {
        OnboardingPage(
            systemImage: "mic.and.signal.meter.fill",
            title: "Welcome to Recap",
            message: "At the end of each day, just talk about what you did. Recap writes it up, tracks your goals and projects, and turns your days into strong interview stories."
        ) {
            EmptyView()
        }
    }
}

private struct HowItWorksPage: View {
    var body: some View {
        OnboardingPage(
            systemImage: "sparkles",
            title: "How it works",
            message: "A minute a day adds up to a record of everything you've done."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                FeatureRow(systemImage: "mic.fill", title: "Talk through your day", detail: "No typing. Your words are turned into text on your iPhone.")
                FeatureRow(systemImage: "text.alignleft", title: "Get a written summary", detail: "Wins, challenges, skills, and progress, written up by AI.")
                FeatureRow(systemImage: "target", title: "Track goals and projects", detail: "Recap notices what you're working toward and keeps a timeline.")
                FeatureRow(systemImage: "star.square.on.square", title: "See your competencies", detail: "Each day is tagged with the leadership competencies you showed.")
                FeatureRow(systemImage: "briefcase.fill", title: "Ace your interviews", detail: "Describe an interview and get STAR stories built from your real days.")
            }
            .padding(.top, 8)
        }
    }
}

private struct MicrophonePage: View {
    @State private var granted: Bool?

    var body: some View {
        OnboardingPage(
            systemImage: "mic.circle.fill",
            title: "Your voice, your iPhone",
            message: "Recap needs the microphone and speech recognition to turn what you say into text. Speech is processed on your device."
        ) {
            switch granted {
            case true?:
                DoneLabel(text: "Microphone ready")
            case false?:
                Text("No problem. You can turn this on later in the Settings app under Recap.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case nil:
                Button("Allow microphone") {
                    Task { granted = await RecapRecorder.requestAccess() }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .onAppear {
            if SFSpeechRecognizer.authorizationStatus() == .authorized,
               AVAudioApplication.shared.recordPermission == .granted {
                granted = true
            }
        }
    }
}

private struct ReminderPage: View {
    @AppStorage(SettingsKey.reminderEnabled) private var reminderEnabled = false
    @AppStorage(SettingsKey.reminderHour) private var reminderHour = 21
    @AppStorage(SettingsKey.reminderMinute) private var reminderMinute = 0
    @State private var denied = false

    var body: some View {
        OnboardingPage(
            systemImage: "bell.badge.fill",
            title: "A nudge each evening",
            message: "Recap can remind you to record your recap at the end of the day. Tap the reminder and the recorder opens."
        ) {
            VStack(spacing: 14) {
                if reminderEnabled {
                    DoneLabel(text: "Reminder on")
                    DatePicker("Remind me at", selection: time, displayedComponents: .hourAndMinute)
                        .padding()
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                } else {
                    DatePicker("Remind me at", selection: time, displayedComponents: .hourAndMinute)
                        .padding()
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                    Button("Turn on daily reminder") {
                        Task { await enable() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                if denied {
                    Text("Notifications are off for Recap. You can turn them on later in the Settings app.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: Date()) ?? Date()
        } set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = parts.hour ?? 21
            reminderMinute = parts.minute ?? 0
            if reminderEnabled {
                Task { await ReminderScheduler.schedule(hour: reminderHour, minute: reminderMinute) }
            }
        }
    }

    private func enable() async {
        let allowed = await ReminderScheduler.requestAuthorization()
        denied = !allowed
        guard allowed else { return }
        reminderEnabled = true
        await ReminderScheduler.schedule(hour: reminderHour, minute: reminderMinute)
    }
}

private struct AIPage: View {
    @State private var keyField = ""
    @State private var hasKey = AIConfig.claudeKey != nil

    var body: some View {
        OnboardingPage(
            systemImage: "brain",
            title: "Your AI",
            message: "Daily summaries use Apple Intelligence: free, private, and on your iPhone. For the best interview stories, you can also add Claude."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Apple Intelligence: \(AppleIntelligence.statusText)", systemImage: "sparkles")
                    .font(.subheadline)

                if hasKey {
                    DoneLabel(text: "Claude key saved")
                } else {
                    Text("Optional: Claude API key")
                        .font(.headline)
                    Text("Claude Pro doesn't cover apps. The API is pay-as-you-go, usually a few cents per interview prep. You can add this later in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    SecureField("Paste your API key (sk-ant-…)", text: $keyField)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                    HStack {
                        Button("Save key") {
                            KeychainStore.set(keyField, for: AIConfig.claudeKeyAccount)
                            keyField = ""
                            hasKey = AIConfig.claudeKey != nil
                        }
                        .buttonStyle(.bordered)
                        .disabled(keyField.trimmed.isEmpty)
                        Spacer()
                        Link("Get a key", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                            .font(.subheadline)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct BackupPage: View {
    @State private var backups = BackupManager.shared
    @State private var showingPicker = false
    @State private var restoring = false
    @State private var restored = false

    var body: some View {
        OnboardingPage(
            systemImage: "externaldrive.badge.icloud",
            title: "Never lose a day",
            message: "Pick a folder in iCloud Drive and Recap backs up there automatically, so your recaps survive a new phone or a reinstall. The free iCloud storage is plenty."
        ) {
            VStack(spacing: 14) {
                if let folder = backups.folderName {
                    DoneLabel(text: "Backing up to \(folder)")
                    if backups.folderIsInsideApp {
                        Text("This folder is inside Recap itself, so deleting the app deletes it too. Choose a folder in iCloud Drive instead.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }

                // Reinstalling? A backup found in the folder can be restored right here.
                if let offer = backups.restoreOffer, !restored {
                    VStack(spacing: 10) {
                        Text("Found a backup from \(offer.file.createdAt.formatted(date: .long, time: .shortened)) with \(offer.file.preview.description).")
                            .multilineTextAlignment(.center)
                        Button {
                            Task {
                                restoring = true
                                try? await backups.restore(offer.file, mode: .replace)
                                restoring = false
                                restored = true
                            }
                        } label: {
                            if restoring { ProgressView() } else { Text("Restore it") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(restoring)
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }
                if restored {
                    DoneLabel(text: "Your backup is restored")
                }

                Button(backups.hasFolder ? "Choose a different folder" : "Choose backup folder") {
                    showingPicker = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await backups.chooseFolder(url) }
            }
        }
    }
}

private struct ReadyPage: View {
    var onFinish: (_ startRecording: Bool) -> Void

    var body: some View {
        OnboardingPage(
            systemImage: "checkmark.seal.fill",
            title: "You're all set",
            message: "Try your first recap now. Just talk about your day, even if it's short."
        ) {
            VStack(spacing: 12) {
                Button {
                    onFinish(true)
                } label: {
                    Label("Record my first recap", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Explore the app first") { onFinish(false) }
                    .controlSize(.large)
                Text("You can see this tour again in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 420)
        }
    }
}

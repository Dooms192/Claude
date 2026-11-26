import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var backups = BackupManager.shared
    @State private var restoreError: String?

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.tab) {
            Tab("Journal", systemImage: "book.closed", value: AppTab.journal) {
                JournalView()
            }
            Tab("Projects", systemImage: "square.stack.3d.up", value: AppTab.projects) {
                ProjectsView()
            }
            Tab("Goals", systemImage: "target", value: AppTab.goals) {
                GoalsView()
            }
            Tab("Interview", systemImage: "briefcase", value: AppTab.interview) {
                InterviewTab()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        // Presented from the top of the app, so the recorder survives the window
        // resizing when the Duo folds or unfolds.
        .sheet(isPresented: $router.showRecorder) {
            RecapRecorderView()
        }
        // Any saved change to your data schedules an automatic backup (debounced).
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            backups.noteChange()
        }
        // On first launch with an empty app: "Found a backup from [date]. Restore it?"
        .alert(
            "Restore your backup?",
            isPresented: .init(get: { backups.restoreOffer != nil }, set: { if !$0 { backups.restoreOffer = nil } }),
            presenting: backups.restoreOffer
        ) { offer in
            Button("Restore") {
                Task {
                    do {
                        try await backups.restore(offer.file, mode: .replace)
                    } catch {
                        restoreError = error.localizedDescription
                    }
                }
            }
            Button("Not now", role: .cancel) {}
        } message: { offer in
            Text("Found a backup from \(offer.file.createdAt.formatted(date: .long, time: .shortened)) with \(offer.file.preview.description). Restore it?")
        }
        .alert("Couldn't restore", isPresented: .init(get: { restoreError != nil }, set: { if !$0 { restoreError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreError ?? "")
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .background {
                // Back up on the way out if anything changed since the last backup.
                backups.backupIfNeeded()
                return
            }
            guard phase == .active else { return }
            // Housekeeping runs after the screen is drawn, never before it.
            Task {
                await Task.yield()
                await backups.checkForRestoreOffer()
            }
            // Mark projects you haven't mentioned in 21 days as inactive, and refresh the
            // weekly project pulse so its numbers are current.
            Task {
                await Task.yield()
                ProjectStore.refreshInactivity(in: context)
                await ProjectPulse.reschedule(in: context)
                await CompetencyPulse.reschedule(in: context)
            }
        }
    }
}

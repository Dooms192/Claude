import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

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
                InterviewPrepView()
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
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            // Mark projects you haven't mentioned in 21 days as inactive, and refresh the
            // weekly project pulse so its numbers are current.
            ProjectStore.refreshInactivity(in: context)
            Task { await ProjectPulse.reschedule(in: context) }
        }
    }
}

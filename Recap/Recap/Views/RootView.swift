import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.tab) {
            Tab("Journal", systemImage: "book.closed", value: AppTab.journal) {
                JournalView()
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
    }
}

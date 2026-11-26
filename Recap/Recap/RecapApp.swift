import SwiftData
import SwiftUI
import UserNotifications

@main
struct RecapApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Long-lived state lives here, above every view, so folding or unfolding the
    // iPhone Duo (which resizes the window and can rebuild views) never interrupts
    // a recording or loses what you've said.
    @State private var recorder = RecapRecorder()
    @State private var router = AppRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(recorder)
                .environment(router)
        }
        .modelContainer(for: [DayEntry.self, Goal.self, PrepSession.self, Project.self, IgnoredProjectName.self])
    }
}

/// Which tab is showing, and whether the recap recorder is open.
enum AppTab: Hashable {
    case journal, projects, goals, interview, settings
}

/// The Interview tab has two parts: building stories, and browsing your competencies.
enum InterviewMode: Hashable {
    case prep, competencies
}

@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var tab: AppTab = .journal
    var showRecorder = false
    /// Set by "Prep interview stories from this project"; Interview Prep picks it up.
    var interviewProjectID: UUID?
    var interviewMode: InterviewMode = .prep
    /// Set by "Build a STAR story for this competency"; Interview Prep picks it up.
    var interviewCompetencies: [String]?

    func startRecap() {
        tab = .journal
        showRecorder = true
    }

    func prepInterview(for project: Project) {
        interviewProjectID = project.id
        interviewMode = .prep
        tab = .interview
    }

    func prepStories(forCompetencies names: [String]) {
        interviewCompetencies = names
        interviewMode = .prep
        tab = .interview
    }
}

/// Opens the recorder when you tap the end-of-day reminder.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isRecapReminder = response.notification.request.identifier == ReminderScheduler.identifier
        Task { @MainActor in
            if isRecapReminder { AppRouter.shared.startRecap() }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

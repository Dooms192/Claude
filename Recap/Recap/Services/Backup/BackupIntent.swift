import AppIntents
import Foundation

/// "Back up Recap" in the Shortcuts app, so you can run it from a personal automation,
/// for example every night at 10 PM.
struct BackUpRecapIntent: AppIntent {
    static let title: LocalizedStringResource = "Back up Recap"
    static let description = IntentDescription("Saves a backup of your Recap data to your chosen backup folder.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = BackupManager.shared
        manager.configure(container: RecapStore.container)
        guard manager.hasFolder else { throw BackupError.noFolder }
        guard await manager.backupNow() else {
            throw BackupError.folderUnavailable
        }
        return .result(dialog: "Recap is backed up.")
    }
}

struct RecapShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BackUpRecapIntent(),
            phrases: ["Back up \(.applicationName)"],
            shortTitle: "Back up Recap",
            systemImageName: "externaldrive.badge.icloud"
        )
    }
}

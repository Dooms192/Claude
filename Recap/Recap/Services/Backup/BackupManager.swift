import Foundation
import Observation
import SwiftData
import UIKit

/// Automatic backups to a folder you choose, such as one in iCloud Drive. No paid iCloud
/// account or CloudKit needed: backups are plain JSON files.
///
/// - Backs up about 5 seconds after the last change (rapid edits make one backup), and when
///   the app goes to the background with unsaved changes.
/// - Writes to a temporary file in the same folder, then renames it into place, so a crash
///   never leaves a half-written backup. File work happens off the main thread.
/// - Keeps the newest N backups and only ever touches files named `Recap-Backup-…json`.
/// - A failed backup never blocks the app; Settings shows a "Backups paused" banner instead.
@MainActor
@Observable
final class BackupManager {
    static let shared = BackupManager()

    static let keepCountKey = "backupKeepCount"
    static let keepCountOptions = [5, 10, 30]
    private static let bookmarkKey = "backupFolderBookmark"
    private static let lastBackupKey = "backupLastSuccess"
    static let filePrefix = "Recap-Backup-"

    /// The chosen folder's name, for display.
    private(set) var folderName: String?
    private(set) var lastBackupAt: Date?
    private(set) var isBackingUp = false
    /// Set when backups can't be written; shown as a banner in Settings.
    private(set) var pausedMessage: String?
    /// True when the chosen folder is inside the app's own storage, which is deleted with the app.
    private(set) var folderIsInsideApp = false
    private(set) var folderIsInICloud = false
    /// A backup found in the folder while the app is empty: "Found a backup from…".
    var restoreOffer: RestoreOffer?

    var hasFolder: Bool { folderName != nil }

    var keepCount: Int {
        get {
            access(keyPath: \.keepCount)
            let stored = UserDefaults.standard.integer(forKey: Self.keepCountKey)
            return stored > 0 ? stored : 10
        }
        set {
            withMutation(keyPath: \.keepCount) {
                UserDefaults.standard.set(newValue, forKey: Self.keepCountKey)
            }
        }
    }

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var hasUnsavedChanges = false
    @ObservationIgnored private var pendingBackup: Task<Void, Never>?
    /// Changes made while restoring shouldn't each trigger their own backup.
    @ObservationIgnored private(set) var isRestoring = false

    struct RestoreOffer: Identifiable {
        let url: URL
        let file: BackupFile
        var id: URL { url }
    }

    private init() {
        lastBackupAt = UserDefaults.standard.object(forKey: Self.lastBackupKey) as? Date
        // Looking up the saved folder can be slow (iCloud Drive), so it happens just after
        // launch instead of before the first screen is drawn.
        Task { @MainActor in self.loadSavedFolder() }
    }

    func loadSavedFolder() {
        guard folderName == nil, let folder = try? resolveFolder() else { return }
        folderName = folder.lastPathComponent
        updateFolderFlags(for: folder)
    }

    func configure(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Folder

    /// Saves the folder you picked as a bookmark, so backups keep working after relaunches.
    func chooseFolder(_ url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            folderName = url.lastPathComponent
            updateFolderFlags(for: url)
            pausedMessage = nil
        } catch {
            pausedMessage = "Couldn't use that folder: \(error.localizedDescription)"
            return
        }
        // Back up right away, and if the app is empty, offer to restore a backup found there.
        await backupNow()
        await checkForRestoreOffer()
    }

    private func resolveFolder() throws -> URL {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { throw BackupError.noFolder }
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        if isStale {
            // Refresh the bookmark while we still have access.
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
            } else {
                throw BackupError.folderUnavailable
            }
        }
        return url
    }

    private func updateFolderFlags(for url: URL) {
        let path = url.resolvingSymlinksInPath().path
        let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
        folderIsInsideApp = path.hasPrefix(home)
        folderIsInICloud = path.contains("Mobile Documents")
    }

    // MARK: - Automatic backups

    /// Called whenever app data is saved. Backs up about 5 seconds after the last change.
    func noteChange() {
        guard !isRestoring else { return }
        hasUnsavedChanges = true
        guard hasFolder else { return }
        pendingBackup?.cancel()
        pendingBackup = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.backupNow()
        }
    }

    /// Called when the app goes to the background.
    func backupIfNeeded() {
        guard hasUnsavedChanges, hasFolder else { return }
        pendingBackup?.cancel()
        // Ask iOS for a little time to finish, since the app is leaving the screen.
        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "Recap backup") {
            UIApplication.shared.endBackgroundTask(taskID)
        }
        Task {
            await backupNow()
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }

    /// Writes a backup now. Returns true if it succeeded.
    @discardableResult
    func backupNow(suffix: String? = nil) async -> Bool {
        guard let container else { return false }
        let folder: URL
        do {
            folder = try resolveFolder()
        } catch BackupError.noFolder {
            return false
        } catch {
            pausedMessage = BackupError.folderUnavailable.errorDescription
            return false
        }

        isBackingUp = true
        defer { isBackingUp = false }
        hasUnsavedChanges = false

        do {
            let data = try BackupFile.make(from: container.mainContext).encoded()
            let name = Self.fileName(for: Date(), suffix: suffix)
            let keep = keepCount
            try await Task.detached(priority: .utility) {
                try BackupFiles.write(data, named: name, in: folder, keep: keep)
            }.value
            lastBackupAt = Date()
            UserDefaults.standard.set(lastBackupAt, forKey: Self.lastBackupKey)
            pausedMessage = nil
            return true
        } catch {
            hasUnsavedChanges = true
            pausedMessage = (error as? BackupError)?.errorDescription ?? BackupError.folderUnavailable.errorDescription
            return false
        }
    }

    static func fileName(for date: Date, suffix: String? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let stamp = formatter.string(from: date)
        return "\(filePrefix)\(stamp)\(suffix.map { "-\($0)" } ?? "").json"
    }

    // MARK: - Restoring

    /// Reads a backup file you picked in the file picker.
    func readBackup(at url: URL) async throws -> BackupFile {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try await Task.detached(priority: .userInitiated) {
            try BackupFiles.read(url)
        }.value
        return try BackupFile.decode(data)
    }

    /// Makes a safety backup of what's in the app now, then restores `file`.
    func restore(_ file: BackupFile, mode: RestoreMode) async throws {
        guard let container else { return }
        let context = container.mainContext

        let current = try BackupFile.make(from: context)
        if !current.isEmpty {
            try await saveSafetyBackup(current)
        }

        isRestoring = true
        defer { isRestoring = false }
        try file.restore(into: context, mode: mode)
        restoreOffer = nil
        // The restored data becomes the newest backup.
        isRestoring = false
        await backupNow()
    }

    /// Saves a "before-restore" copy, to your backup folder if you have one, otherwise to
    /// Files → On My iPhone → Recap.
    private func saveSafetyBackup(_ current: BackupFile) async throws {
        let data = try current.encoded()
        let name = Self.fileName(for: Date(), suffix: "before-restore")
        let folder = (try? resolveFolder())
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // Safety copies aren't pruned with the regular backups' count right away.
        try await Task.detached(priority: .userInitiated) {
            try BackupFiles.write(data, named: name, in: folder, keep: nil)
        }.value
    }

    /// If the app is empty and the backup folder has a backup, offers to restore it.
    func checkForRestoreOffer() async {
        guard let container, restoreOffer == nil else { return }
        let context = container.mainContext
        let entries = (try? context.fetchCount(FetchDescriptor<DayEntry>())) ?? 0
        let goals = (try? context.fetchCount(FetchDescriptor<Goal>())) ?? 0
        guard entries == 0, goals == 0, let folder = try? resolveFolder() else { return }

        let newest = try? await Task.detached(priority: .utility, operation: {
            try BackupFiles.newestBackup(in: folder)
        }).value
        guard let newest, let file = try? BackupFile.decode(newest.data), !file.isEmpty else { return }
        restoreOffer = RestoreOffer(url: newest.url, file: file)
    }
}

/// The file work, done off the main thread. Only touches files named `Recap-Backup-…json`.
enum BackupFiles {
    static func write(_ data: Data, named name: String, in folder: URL, keep: Int?) throws {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: folder.path) else { throw BackupError.folderUnavailable }

        let destination = folder.appendingPathComponent(name)
        // A hidden temp file in the same folder, so the final rename is atomic.
        let temp = folder.appendingPathComponent(".\(name).\(UUID().uuidString).tmp")

        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { url in
            do {
                try data.write(to: temp, options: .atomic)
                if FileManager.default.fileExists(atPath: url.path) {
                    _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
                } else {
                    try FileManager.default.moveItem(at: temp, to: url)
                }
            } catch {
                try? FileManager.default.removeItem(at: temp)
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }

        if let keep { try prune(folder, keep: keep) }
    }

    /// Deletes the oldest automatic backups beyond `keep`. Never touches other files.
    static func prune(_ folder: URL, keep: Int) throws {
        let backups = try backupFiles(in: folder)
            .filter { !$0.lastPathComponent.contains("-before-restore") }
        guard backups.count > keep else { return }
        for url in backups.dropFirst(keep) {
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { url in
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Backup files in the folder, newest first (the date in the name sorts correctly).
    static func backupFiles(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter {
                $0.lastPathComponent.hasPrefix(BackupManager.filePrefix) && $0.pathExtension == "json"
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func newestBackup(in folder: URL) throws -> (url: URL, data: Data)? {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        guard let newest = try backupFiles(in: folder).first else { return nil }
        return (url: newest, data: try read(newest))
    }

    /// Reads a file, letting iCloud Drive download it first if needed.
    static func read(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(BackupError.notABackup)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}

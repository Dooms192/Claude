import Foundation
import SwiftData

// The backup file format.
//
// Rules for keeping old backups readable:
// - Never remove or rename a field. Add new fields as Optionals, so files written before
//   the field existed still decode (a missing Optional decodes as nil).
// - When a change can't be expressed that way, bump `BackupFile.currentFormat` and add a
//   step to `BackupFile.decode` that upgrades the older shape.
// - Unknown fields are ignored when reading, so an older app can still read the parts it
//   understands from a newer file only if the format number allows it (see `decode`).

/// One complete backup: everything in the app except the Claude API key.
struct BackupFile: Codable, Sendable {
    /// Bump when the format changes in a way old readers can't handle.
    static let currentFormat = 1

    var formatVersion: Int
    var app: String
    var createdAt: Date
    var entries: [EntryRecord]
    var goals: [GoalRecord]
    var projects: [ProjectRecord]
    var prepSessions: [PrepRecord]
    var ignoredProjectNames: [String]
    var settings: SettingsRecord

    struct EntryRecord: Codable, Sendable {
        var id: UUID
        var date: Date
        var createdAt: Date
        var transcript: String
        var headline: String
        var summary: String
        var accomplishments: [String]
        var challenges: [String]
        var skills: [String]
        var goalUpdates: [GoalUpdate]
        var suggestedGoals: [GoalUpdate]?
        var summarizedBy: String
        var summarizedAt: Date?
        var projectNotes: [ProjectNote]?
        var competencyTags: [CompetencyTag]?
        var competenciesTaggedAt: Date?
        /// Links, stored by ID so they can be rebuilt on restore.
        var goalIDs: [UUID]
        var projectIDs: [UUID]?
    }

    struct GoalRecord: Codable, Sendable {
        var id: UUID
        var title: String
        var details: String
        var createdAt: Date
        var targetDate: Date?
        var isArchived: Bool
    }

    struct ProjectRecord: Codable, Sendable {
        var id: UUID
        var name: String
        var details: String
        var status: String
        var startDate: Date
        var lastMentioned: Date
        var targetDate: Date?
        var stillWorkingConfirmedAt: Date?
        var insight: ProjectInsight?
        var insightUpdatedAt: Date?
        var colorName: String
        var icon: String
        var createdAt: Date
    }

    struct PrepRecord: Codable, Sendable {
        var id: UUID
        var createdAt: Date
        var query: String
        var engine: String
        var note: String?
        var entriesUsed: Int
        var prep: InterviewPrep?
        var projectName: String?
        var competencyNames: [String]?
    }

    /// Settings worth keeping. Never the API key.
    struct SettingsRecord: Codable, Sendable {
        var summaryEngine: String?
        var interviewEngine: String?
        var reminderEnabled: Bool?
        var reminderHour: Int?
        var reminderMinute: Int?
        var projectPulseEnabled: Bool?
        var competencyPulseEnabled: Bool?
        var backupKeepCount: Int?
    }

    // MARK: - Reading and writing

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Reads any backup this version of the app understands, upgrading older formats.
    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        struct Header: Decodable { var formatVersion: Int? }
        guard let version = try? decoder.decode(Header.self, from: data).formatVersion else {
            throw BackupError.notABackup
        }
        guard version <= currentFormat else { throw BackupError.newerFormat(version) }

        switch version {
        case 1:
            return try decoder.decode(BackupFile.self, from: data)
        // Future formats: decode the old shape here and convert it to the current one.
        default:
            throw BackupError.notABackup
        }
    }

    var preview: BackupPreview {
        BackupPreview(
            createdAt: createdAt,
            recaps: entries.count,
            goals: goals.count,
            projects: projects.count,
            preps: prepSessions.count
        )
    }

    var isEmpty: Bool {
        entries.isEmpty && goals.isEmpty && projects.isEmpty && prepSessions.isEmpty
    }
}

/// A summary shown before restoring.
struct BackupPreview: Sendable, Equatable {
    var createdAt: Date
    var recaps: Int
    var goals: Int
    var projects: Int
    var preps: Int

    var description: String {
        "\(recaps) recap\(recaps == 1 ? "" : "s"), \(goals) goal\(goals == 1 ? "" : "s"), \(projects) project\(projects == 1 ? "" : "s"), \(preps) interview prep\(preps == 1 ? "" : "s")"
    }
}

enum BackupError: LocalizedError {
    case noFolder
    case folderUnavailable
    case notABackup
    case newerFormat(Int)

    var errorDescription: String? {
        switch self {
        case .noFolder:
            return "Choose a backup folder in Recap's Settings first."
        case .folderUnavailable:
            return "Backups paused: choose your folder again."
        case .notABackup:
            return "This file isn't a Recap backup."
        case .newerFormat:
            return "This backup was made by a newer version of Recap. Update the app to restore it."
        }
    }
}

// MARK: - Building a backup from the app's data

extension BackupFile {
    @MainActor
    static func make(from context: ModelContext) throws -> BackupFile {
        let entries = try context.fetch(FetchDescriptor<DayEntry>())
        let goals = try context.fetch(FetchDescriptor<Goal>())
        let projects = try context.fetch(FetchDescriptor<Project>())
        let preps = try context.fetch(FetchDescriptor<PrepSession>())
        let ignored = try context.fetch(FetchDescriptor<IgnoredProjectName>())
        let defaults = UserDefaults.standard

        return BackupFile(
            formatVersion: currentFormat,
            app: "Recap",
            createdAt: Date(),
            entries: entries.map { entry in
                EntryRecord(
                    id: entry.id,
                    date: entry.date,
                    createdAt: entry.createdAt,
                    transcript: entry.transcript,
                    headline: entry.headline,
                    summary: entry.summary,
                    accomplishments: entry.accomplishments,
                    challenges: entry.challenges,
                    skills: entry.skills,
                    goalUpdates: entry.goalUpdates,
                    suggestedGoals: entry.suggestedGoals,
                    summarizedBy: entry.summarizedBy,
                    summarizedAt: entry.summarizedAt,
                    projectNotes: entry.projectNotes,
                    competencyTags: entry.competencyTags,
                    competenciesTaggedAt: entry.competenciesTaggedAt,
                    goalIDs: (entry.goals ?? []).map(\.id),
                    projectIDs: (entry.projects ?? []).map(\.id)
                )
            },
            goals: goals.map {
                GoalRecord(
                    id: $0.id, title: $0.title, details: $0.details, createdAt: $0.createdAt,
                    targetDate: $0.targetDate, isArchived: $0.isArchived
                )
            },
            projects: projects.map {
                ProjectRecord(
                    id: $0.id, name: $0.name, details: $0.details, status: $0.statusRaw,
                    startDate: $0.startDate, lastMentioned: $0.lastMentioned, targetDate: $0.targetDate,
                    stillWorkingConfirmedAt: $0.stillWorkingConfirmedAt, insight: $0.insight,
                    insightUpdatedAt: $0.insightUpdatedAt, colorName: $0.colorName, icon: $0.icon,
                    createdAt: $0.createdAt
                )
            },
            prepSessions: preps.map {
                PrepRecord(
                    id: $0.id, createdAt: $0.createdAt, query: $0.query, engine: $0.engine,
                    note: $0.note, entriesUsed: $0.entriesUsed, prep: $0.prep,
                    projectName: $0.projectName, competencyNames: $0.competencyNames
                )
            },
            ignoredProjectNames: ignored.map(\.name),
            settings: SettingsRecord(
                summaryEngine: defaults.string(forKey: SettingsKey.summaryEngine),
                interviewEngine: defaults.string(forKey: SettingsKey.interviewEngine),
                reminderEnabled: defaults.object(forKey: SettingsKey.reminderEnabled) as? Bool,
                reminderHour: defaults.object(forKey: SettingsKey.reminderHour) as? Int,
                reminderMinute: defaults.object(forKey: SettingsKey.reminderMinute) as? Int,
                projectPulseEnabled: defaults.object(forKey: ProjectPulse.enabledKey) as? Bool,
                competencyPulseEnabled: defaults.object(forKey: CompetencyPulse.enabledKey) as? Bool,
                backupKeepCount: defaults.object(forKey: BackupManager.keepCountKey) as? Int
            )
        )
    }
}

// MARK: - Restoring a backup into the app

enum RestoreMode {
    /// Delete everything, then load the backup.
    case replace
    /// Add anything from the backup that's missing, matched by ID. Nothing is duplicated
    /// and nothing you have now is changed.
    case merge
}

extension BackupFile {
    @MainActor
    func restore(into context: ModelContext, mode: RestoreMode) throws {
        if mode == .replace {
            for entry in try context.fetch(FetchDescriptor<DayEntry>()) { context.delete(entry) }
            for goal in try context.fetch(FetchDescriptor<Goal>()) { context.delete(goal) }
            for project in try context.fetch(FetchDescriptor<Project>()) { context.delete(project) }
            for prep in try context.fetch(FetchDescriptor<PrepSession>()) { context.delete(prep) }
            for name in try context.fetch(FetchDescriptor<IgnoredProjectName>()) { context.delete(name) }
            try context.save()
        }

        // Goals and projects first, so recaps can link to them.
        var goalsByID = Dictionary(
            try context.fetch(FetchDescriptor<Goal>()).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for record in goals where goalsByID[record.id] == nil {
            let goal = Goal(title: record.title, details: record.details, targetDate: record.targetDate)
            goal.id = record.id
            goal.createdAt = record.createdAt
            goal.isArchived = record.isArchived
            context.insert(goal)
            goalsByID[record.id] = goal
        }

        var projectsByID = Dictionary(
            try context.fetch(FetchDescriptor<Project>()).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for record in projects where projectsByID[record.id] == nil {
            let project = Project(name: record.name, details: record.details, startDate: record.startDate)
            project.id = record.id
            project.statusRaw = record.status
            project.lastMentioned = record.lastMentioned
            project.targetDate = record.targetDate
            project.stillWorkingConfirmedAt = record.stillWorkingConfirmedAt
            if let insight = record.insight { project.setInsight(insight) }
            project.insightUpdatedAt = record.insightUpdatedAt
            project.colorName = record.colorName
            project.icon = record.icon
            project.createdAt = record.createdAt
            context.insert(project)
            projectsByID[record.id] = project
        }

        let existingEntryIDs = Set(try context.fetch(FetchDescriptor<DayEntry>()).map(\.id))
        for record in entries where !existingEntryIDs.contains(record.id) {
            let entry = DayEntry(transcript: record.transcript, recordedAt: record.createdAt)
            entry.id = record.id
            entry.date = record.date
            entry.createdAt = record.createdAt
            entry.headline = record.headline
            entry.summary = record.summary
            entry.accomplishments = record.accomplishments
            entry.challenges = record.challenges
            entry.skills = record.skills
            entry.goalUpdates = record.goalUpdates
            entry.suggestedGoals = record.suggestedGoals ?? []
            entry.summarizedBy = record.summarizedBy
            entry.summarizedAt = record.summarizedAt
            entry.projectNotes = record.projectNotes ?? []
            entry.competencyTags = record.competencyTags ?? []
            entry.competenciesTaggedAt = record.competenciesTaggedAt
            context.insert(entry)

            // Relink goals and projects by ID, so goal progress and project timelines work.
            entry.goals = record.goalIDs.compactMap { goalsByID[$0] }
            var linked = (record.projectIDs ?? []).compactMap { projectsByID[$0] }
            // Fallback for any project link missing from the file: match the day's
            // project notes by name.
            for note in entry.projectNotes where !linked.contains(where: { $0.name.normalizedKey == note.projectName.normalizedKey }) {
                if let project = projectsByID.values.first(where: { $0.name.normalizedKey == note.projectName.normalizedKey }) {
                    linked.append(project)
                }
            }
            entry.projects = linked
            // Competency evidence is read straight from each day's tags, so it needs no relinking.
        }

        let existingPrepIDs = Set(try context.fetch(FetchDescriptor<PrepSession>()).map(\.id))
        for record in prepSessions where !existingPrepIDs.contains(record.id) {
            guard let prep = record.prep else { continue }
            let session = PrepSession(
                query: record.query,
                engine: record.engine,
                note: record.note,
                entriesUsed: record.entriesUsed,
                prep: prep,
                projectName: record.projectName,
                competencyNames: record.competencyNames ?? []
            )
            session.id = record.id
            session.createdAt = record.createdAt
            context.insert(session)
        }

        let existingIgnored = Set(try context.fetch(FetchDescriptor<IgnoredProjectName>()).map { $0.name.normalizedKey })
        for name in ignoredProjectNames where !existingIgnored.contains(name.normalizedKey) {
            context.insert(IgnoredProjectName(name: name))
        }

        if mode == .replace { settings.apply() }
        try context.save()
    }
}

extension BackupFile.SettingsRecord {
    /// Restores settings. The API key is never part of a backup.
    func apply() {
        let defaults = UserDefaults.standard
        if let summaryEngine { defaults.set(summaryEngine, forKey: SettingsKey.summaryEngine) }
        if let interviewEngine { defaults.set(interviewEngine, forKey: SettingsKey.interviewEngine) }
        if let reminderHour { defaults.set(reminderHour, forKey: SettingsKey.reminderHour) }
        if let reminderMinute { defaults.set(reminderMinute, forKey: SettingsKey.reminderMinute) }
        if let reminderEnabled { defaults.set(reminderEnabled, forKey: SettingsKey.reminderEnabled) }
        if let projectPulseEnabled { defaults.set(projectPulseEnabled, forKey: ProjectPulse.enabledKey) }
        if let competencyPulseEnabled { defaults.set(competencyPulseEnabled, forKey: CompetencyPulse.enabledKey) }
        if let backupKeepCount { defaults.set(backupKeepCount, forKey: BackupManager.keepCountKey) }

        let hour = defaults.object(forKey: SettingsKey.reminderHour) as? Int ?? 21
        let minute = defaults.object(forKey: SettingsKey.reminderMinute) as? Int ?? 0
        if reminderEnabled == true {
            Task { await ReminderScheduler.schedule(hour: hour, minute: minute) }
        }
    }
}

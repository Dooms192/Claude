import Foundation
import SwiftData

/// Everything that creates, renames, merges, or updates projects, so recaps and
/// projects always stay in sync.
@MainActor
enum ProjectStore {
    /// A project with no mention for this long is marked inactive.
    static let inactivityDays = 21

    // MARK: - Mentions from recaps

    /// Updates a project after a recap mentions it.
    static func recordMention(of project: Project, in entry: DayEntry) {
        if entry.date < project.startDate { project.startDate = entry.date }
        if entry.date >= project.lastMentioned {
            project.lastMentioned = entry.date
            // The newest mention decides the status: finishing it completes the
            // project, and any other mention means you're actively on it again.
            if let signal = project.note(in: entry)?.signal {
                project.status = signal == .completed ? .completed : .active
            }
        }
    }

    // MARK: - New project cards

    /// "Add": creates a project from a detected name and links every recap that mentions it.
    @discardableResult
    static func create(from detection: ProjectNote, named newName: String? = nil, in context: ModelContext) -> Project {
        let name = (newName ?? detection.projectName).trimmed
        if name.normalizedKey != detection.projectName.normalizedKey {
            renameNotes(from: detection.projectName, to: name, in: allEntries(context))
        }
        let project = Project(name: name)
        context.insert(project)
        relink(project, in: context)
        try? context.save()
        return project
    }

    /// "Merge": the detected name was really an existing project.
    static func merge(detection: ProjectNote, into project: Project, in context: ModelContext) {
        renameNotes(from: detection.projectName, to: project.name, in: allEntries(context))
        relink(project, in: context)
        try? context.save()
    }

    /// "Ignore": remembers the name so it isn't suggested again.
    static func ignore(_ name: String, in context: ModelContext) {
        context.insert(IgnoredProjectName(name: name))
        try? context.save()
    }

    // MARK: - Editing projects

    static func rename(_ project: Project, to newName: String, in context: ModelContext) {
        let newName = newName.trimmed
        guard !newName.isEmpty, newName != project.name else { return }
        renameNotes(from: project.name, to: newName, in: allEntries(context))
        project.name = newName
        relink(project, in: context)
        try? context.save()
    }

    /// Moves everything from `source` into `target`, then deletes `source`.
    static func merge(_ source: Project, into target: Project, in context: ModelContext) {
        guard source.id != target.id else { return }
        renameNotes(from: source.name, to: target.name, in: allEntries(context))
        if target.targetDate == nil { target.targetDate = source.targetDate }
        if target.details.isEmpty { target.details = source.details }
        context.delete(source)
        relink(target, in: context)
        try? context.save()
    }

    /// Deletes the project and its daily notes. Your recaps themselves stay.
    static func delete(_ project: Project, in context: ModelContext) {
        let key = project.name.normalizedKey
        for entry in allEntries(context) {
            entry.projectNotes.removeAll { $0.projectName.normalizedKey == key }
        }
        context.delete(project)
        try? context.save()
    }

    /// "Still working on this?" → yes.
    static func confirmStillWorking(_ project: Project) {
        project.stillWorkingConfirmedAt = Date()
        project.status = .active
    }

    /// Marks active projects you haven't mentioned in 21 days as inactive.
    static func refreshInactivity(in context: ModelContext) {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let cutoff = Calendar.current.date(byAdding: .day, value: -inactivityDays, to: Date()) ?? Date()
        var changed = false
        for project in projects where project.status == .active && project.lastActivity < cutoff {
            project.status = .inactive
            changed = true
        }
        if changed { try? context.save() }
    }

    // MARK: - Helpers

    /// Links `project` to every recap with a note under its name and recalculates its dates.
    static func relink(_ project: Project, in context: ModelContext) {
        let key = project.name.normalizedKey
        let mentioning = allEntries(context).filter { entry in
            entry.projectNotes.contains { $0.projectName.normalizedKey == key }
        }
        project.entries = mentioning
        guard let first = mentioning.map(\.date).min(), let last = mentioning.map(\.date).max() else { return }
        project.startDate = first
        project.lastMentioned = last
        if let newest = mentioning.max(by: { $0.date < $1.date }), let signal = project.note(in: newest)?.signal {
            project.status = signal == .completed ? .completed : .active
        }
    }

    /// Rewrites daily notes from one project name to another, combining notes when a
    /// day already has one under the new name.
    private static func renameNotes(from oldName: String, to newName: String, in entries: [DayEntry]) {
        let oldKey = oldName.normalizedKey
        let newKey = newName.normalizedKey
        for entry in entries where entry.projectNotes.contains(where: { $0.projectName.normalizedKey == oldKey }) {
            var result: [ProjectNote] = []
            for var note in entry.projectNotes {
                if note.projectName.normalizedKey == oldKey { note.projectName = newName }
                if note.projectName.normalizedKey == newKey,
                   let index = result.firstIndex(where: { $0.projectName.normalizedKey == newKey }) {
                    result[index].note += " " + note.note
                    result[index].blockers += note.blockers
                    result[index].nextSteps += note.nextSteps
                    if note.signal == .completed || note.signal == .blocked { result[index].status = note.status }
                } else {
                    result.append(note)
                }
            }
            entry.projectNotes = result
        }
    }

    private static func allEntries(_ context: ModelContext) -> [DayEntry] {
        (try? context.fetch(FetchDescriptor<DayEntry>())) ?? []
    }
}

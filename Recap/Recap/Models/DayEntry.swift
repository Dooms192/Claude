import Foundation
import SwiftData

/// One spoken end-of-day recap, plus the AI's structured summary of it.
@Model
final class DayEntry {
    var id: UUID = UUID()
    /// The day this recap is about (start of day).
    var date: Date = Date()
    var createdAt: Date = Date()

    /// Exactly what you said, after speech-to-text (and any edits you made).
    var transcript: String = ""

    // AI summary. Empty until summarized.
    var headline: String = ""
    var summary: String = ""
    var accomplishments: [String] = []
    var challenges: [String] = []
    var skills: [String] = []
    var goalUpdates: [GoalUpdate] = []
    /// Goals the AI noticed you working toward that aren't in your Goals list yet.
    /// They're shown as suggestions you can add with one tap. Nothing is created automatically.
    var suggestedGoals: [GoalUpdate] = []
    var summarizedBy: String = ""
    var summarizedAt: Date?

    @Relationship(inverse: \Goal.entries)
    var goals: [Goal]? = []

    /// What this day's recap said about each project you worked on.
    var projectNotes: [ProjectNote] = []

    @Relationship(inverse: \Project.entries)
    var projects: [Project]? = []

    init(transcript: String, recordedAt: Date = Date()) {
        self.transcript = transcript
        self.createdAt = recordedAt
        self.date = DayEntry.recapDay(for: recordedAt)
    }

    var isSummarized: Bool { !summary.isEmpty }

    var displayTitle: String {
        if !headline.isEmpty { return headline }
        return "Recap (not summarized yet)"
    }

    /// Recaps recorded just after midnight are about the day that just ended.
    static func recapDay(for moment: Date, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: moment)
        let day = hour < 4 ? calendar.date(byAdding: .day, value: -1, to: moment) ?? moment : moment
        return calendar.startOfDay(for: day)
    }

    /// Everything about this day as one string, used for search.
    var searchableText: String {
        ([headline, summary, transcript] + accomplishments + challenges + skills
            + goalUpdates.map { "\($0.goalTitle) \($0.note)" }
            + projectNotes.map { "\($0.projectName) \($0.note)" })
            .joined(separator: " ")
    }

    func apply(_ result: DailySummary, engine: String, goals allGoals: [Goal]) {
        headline = result.headline
        summary = result.summary
        accomplishments = result.accomplishments
        challenges = result.challenges
        skills = result.skills
        goalUpdates = result.goalUpdates
        suggestedGoals = result.suggestedGoals
        summarizedBy = engine
        summarizedAt = Date()

        let mentioned = Set(result.goalUpdates.map { $0.goalTitle.normalizedKey })
        goals = allGoals.filter { mentioned.contains($0.title.normalizedKey) }

        // If you mentioned a deadline for a goal that doesn't have one yet, set it.
        for goal in goals ?? [] where goal.targetDate == nil {
            goal.targetDate = result.goalUpdates
                .first { $0.goalTitle.normalizedKey == goal.title.normalizedKey }?
                .deadline
        }
    }

    /// Saves this day's project notes and links the day to projects you already have.
    /// Names that don't match an existing project become "New project detected" cards.
    @MainActor
    func applyProjects(_ notes: [ProjectNote], existing projects: [Project]) {
        projectNotes = notes.filter { !$0.projectName.trimmed.isEmpty }
        let mentioned = Set(projectNotes.map { $0.projectName.normalizedKey })
        let matched = projects.filter { mentioned.contains($0.name.normalizedKey) }
        self.projects = matched
        for project in matched {
            ProjectStore.recordMention(of: project, in: self)
        }
    }

    /// Project names in this recap that aren't projects yet and that you haven't ignored.
    func projectDetections(existing projects: [Project], ignored: Set<String>) -> [ProjectNote] {
        var seen = Set(projects.map { $0.name.normalizedKey }).union(ignored)
        return projectNotes.filter { seen.insert($0.projectName.normalizedKey).inserted }
    }

    func note(for goal: Goal) -> String? {
        goalUpdates.first { $0.goalTitle.normalizedKey == goal.title.normalizedKey }?.note
    }

    /// Progress on goals that actually exist in your Goals list.
    func progressUpdates(existing goals: [Goal]) -> [GoalUpdate] {
        let known = Set(goals.map { $0.title.normalizedKey })
        return goalUpdates.filter { known.contains($0.goalTitle.normalizedKey) }
    }

    /// Goals mentioned in this recap that aren't in your Goals list yet. This also catches
    /// progress the AI attributed to a goal you never created (as in recaps saved before
    /// suggestions existed).
    func goalSuggestions(existing goals: [Goal]) -> [GoalUpdate] {
        var seen = Set(goals.map { $0.title.normalizedKey })
        var result: [GoalUpdate] = []
        for item in goalUpdates + suggestedGoals where !item.goalTitle.trimmed.isEmpty {
            if seen.insert(item.goalTitle.normalizedKey).inserted { result.append(item) }
        }
        return result
    }

    func dismissSuggestion(_ title: String) {
        let key = title.normalizedKey
        suggestedGoals.removeAll { $0.goalTitle.normalizedKey == key }
        goalUpdates.removeAll { $0.goalTitle.normalizedKey == key }
    }
}

/// Connects goals to the recaps that mention them.
@MainActor
enum GoalLinker {
    /// Creates a goal and links every past recap that mentioned it.
    @discardableResult
    static func createGoal(
        title: String,
        details: String = "",
        targetDate: Date? = nil,
        in context: ModelContext
    ) -> Goal {
        let goal = Goal(title: title.trimmed, details: details, targetDate: targetDate)
        context.insert(goal)
        link(goal, in: context)
        return goal
    }

    /// Links `goal` to every recap that mentions its title, as progress or as a suggestion.
    /// Called when a goal is created or renamed.
    static func link(_ goal: Goal, in context: ModelContext) {
        let key = goal.title.normalizedKey
        let entries = (try? context.fetch(FetchDescriptor<DayEntry>())) ?? []
        for entry in entries {
            if let index = entry.suggestedGoals.firstIndex(where: { $0.goalTitle.normalizedKey == key }) {
                let suggestion = entry.suggestedGoals.remove(at: index)
                if !entry.goalUpdates.contains(where: { $0.goalTitle.normalizedKey == key }) {
                    entry.goalUpdates.append(
                        GoalUpdate(goalTitle: goal.title, note: suggestion.note, targetDate: suggestion.targetDate)
                    )
                }
            }
            if goal.targetDate == nil,
               let deadline = entry.goalUpdates.first(where: { $0.goalTitle.normalizedKey == key })?.deadline {
                goal.targetDate = deadline
            }
            if entry.goalUpdates.contains(where: { $0.goalTitle.normalizedKey == key }),
               !(entry.goals ?? []).contains(where: { $0.id == goal.id }) {
                entry.goals = (entry.goals ?? []) + [goal]
            }
        }
        try? context.save()
    }
}

struct GoalUpdate: Codable, Hashable, Sendable {
    var goalTitle: String
    var note: String
    /// A deadline you mentioned for this goal, as YYYY-MM-DD. Nil or empty if none.
    var targetDate: String? = nil

    var deadline: Date? { targetDate.flatMap(DayFormat.parse) }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var normalizedKey: String { trimmed.lowercased() }
}

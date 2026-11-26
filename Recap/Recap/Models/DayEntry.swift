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
    var summarizedBy: String = ""
    var summarizedAt: Date?

    @Relationship(inverse: \Goal.entries)
    var goals: [Goal]? = []

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
            + goalUpdates.map { "\($0.goalTitle) \($0.note)" })
            .joined(separator: " ")
    }

    func apply(_ result: DailySummary, engine: String, goals allGoals: [Goal]) {
        headline = result.headline
        summary = result.summary
        accomplishments = result.accomplishments
        challenges = result.challenges
        skills = result.skills
        goalUpdates = result.goalUpdates
        summarizedBy = engine
        summarizedAt = Date()

        let mentioned = Set(result.goalUpdates.map { $0.goalTitle.normalizedKey })
        goals = allGoals.filter { mentioned.contains($0.title.normalizedKey) }
    }

    func note(for goal: Goal) -> String? {
        goalUpdates.first { $0.goalTitle.normalizedKey == goal.title.normalizedKey }?.note
    }
}

struct GoalUpdate: Codable, Hashable, Sendable {
    var goalTitle: String
    var note: String
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var normalizedKey: String { trimmed.lowercased() }
}

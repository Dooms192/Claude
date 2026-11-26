import Foundation

/// A structured summary of one day, from whichever AI engine made it.
struct DailySummary: Codable, Sendable {
    var headline: String
    var summary: String
    var accomplishments: [String]
    var challenges: [String]
    var skills: [String]
    var goalUpdates: [GoalUpdate]
}

protocol RecapSummarizer: Sendable {
    var displayName: String { get }
    func summarize(transcript: String, day: Date, goalTitles: [String]) async throws -> DailySummary
}

protocol InterviewCoachEngine: Sendable {
    var displayName: String { get }
    func prepare(request: String, entries: [EntrySnapshot], totalEntries: Int) async throws -> InterviewPrep
}

/// A plain copy of a journal entry, safe to hand to background AI work.
struct EntrySnapshot: Sendable {
    var day: String
    var headline: String
    var summary: String
    var accomplishments: [String]
    var challenges: [String]
    var skills: [String]
    var goalUpdates: [GoalUpdate]
    var transcript: String

    @MainActor
    init(_ entry: DayEntry) {
        day = DayFormat.iso(entry.date)
        headline = entry.headline
        summary = entry.summary
        accomplishments = entry.accomplishments
        challenges = entry.challenges
        skills = entry.skills
        goalUpdates = entry.goalUpdates
        transcript = entry.transcript
    }

    /// The entry as text for an AI prompt. `transcriptLimit` caps how much raw speech is included.
    func promptBlock(transcriptLimit: Int) -> String {
        var lines = ["<entry date=\"\(day)\">"]
        if !headline.isEmpty { lines.append("Headline: \(headline)") }
        if !summary.isEmpty { lines.append("Summary: \(summary)") }
        if !accomplishments.isEmpty { lines.append("Accomplishments: " + accomplishments.joined(separator: "; ")) }
        if !challenges.isEmpty { lines.append("Challenges: " + challenges.joined(separator: "; ")) }
        if !skills.isEmpty { lines.append("Skills: " + skills.joined(separator: ", ")) }
        if !goalUpdates.isEmpty {
            lines.append("Goal progress: " + goalUpdates.map { "\($0.goalTitle): \($0.note)" }.joined(separator: "; "))
        }
        if transcriptLimit > 0, !transcript.isEmpty {
            let spoken = transcript.count > transcriptLimit
                ? String(transcript.prefix(transcriptLimit)) + "…"
                : transcript
            lines.append("What I said: \(spoken)")
        }
        lines.append("</entry>")
        return lines.joined(separator: "\n")
    }
}

enum DayFormat {
    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }

    static func long(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }
}

/// The instructions given to both AI engines, kept in one place so they behave the same.
enum Prompts {
    static let dailyInstructions = """
    You turn someone's spoken end-of-day recap into a clear journal entry they can use later \
    for tracking goals and preparing for job interviews. The recap was transcribed from speech, \
    so ignore filler words and fix obvious transcription mistakes. Write in the first person ("I"). \
    Only include things the person actually said. Never invent details, numbers, or outcomes. \
    Keep specifics such as names of projects, tools, people's roles, and numbers, because those \
    make strong interview stories later.
    """

    static func dailyPrompt(transcript: String, day: Date, goalTitles: [String]) -> String {
        let goals = goalTitles.isEmpty
            ? "(No goals set yet. Leave goal updates empty.)"
            : goalTitles.map { "- \($0)" }.joined(separator: "\n")
        return """
        Date: \(DayFormat.long(day))

        My current goals:
        \(goals)

        My spoken recap:
        \(transcript)

        Summarize my day. For goal updates, use the exact goal title from my list, and only \
        include goals I actually made progress on today.
        """
    }

    static let interviewInstructions = """
    You are an expert interview coach. You help the user prepare for an interview using only their \
    own daily journal entries, which are provided. Build stories in STAR format: Situation, Task, \
    Action, Result.

    Rules:
    - Use only facts that appear in the entries. Never invent numbers, names, or outcomes.
    - If a story's result isn't recorded, say so in the result and suggest what the user should \
      find out or measure before the interview.
    - Pick the stories that best match what this interviewer is looking for.
    - Combine related entries from different days into one story when they're about the same work.
    - Keep the focus on what the user personally did ("I"), not the team in general.
    - howToSayIt is a natural, first-person answer the user could say out loud in about 60 to 90 seconds.
    - dates lists the entry dates (YYYY-MM-DD) each story draws on.
    - Give 3 to 5 stories, strongest first, and 3 to 6 short, practical tips specific to this interview.
    - If the entries don't contain anything relevant, say so in the overview and give fewer stories.
    """

    static func interviewPrompt(request: String, entries: [EntrySnapshot], totalEntries: Int, transcriptLimit: Int) -> String {
        """
        The interview I'm preparing for:
        \(request)

        Today's date: \(DayFormat.iso(Date()))

        Here are \(entries.count) of my journal entries (the most relevant ones out of \(totalEntries) total):
        <journal_entries>
        \(entries.map { $0.promptBlock(transcriptLimit: transcriptLimit) }.joined(separator: "\n\n"))
        </journal_entries>

        Prepare my interview stories.
        """
    }
}

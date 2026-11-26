import Foundation

/// A structured summary of one day, from whichever AI engine made it.
struct DailySummary: Codable, Sendable {
    var headline: String
    var summary: String
    var accomplishments: [String]
    var challenges: [String]
    var skills: [String]
    var goalUpdates: [GoalUpdate]
    var suggestedGoals: [GoalUpdate]
    var projects: [ProjectNote]
}

protocol RecapSummarizer: Sendable {
    var displayName: String { get }
    func summarize(transcript: String, day: Date, goalTitles: [String], projectNames: [String]) async throws -> DailySummary
}

protocol InterviewCoachEngine: Sendable {
    var displayName: String { get }
    func prepare(request: String, context: InterviewContext) async throws -> InterviewPrep
    /// One STAR story per competency in `context.competencies`.
    func prepareCompetencies(request: String, context: InterviewContext) async throws -> InterviewPrep
}

/// Everything the interview coach gets to work with.
struct InterviewContext: Sendable {
    var entries: [EntrySnapshot]
    var totalEntries: Int
    /// Projects the chosen entries belong to, each with its full timeline, so a
    /// project's story can be told start to finish.
    var projects: [ProjectSnapshot]
    /// Set when you picked "Use stories from: [project]".
    var focusProject: String?
    /// Competencies to build one story each for, with your tagged evidence.
    var competencies: [CompetencyBrief] = []
}

/// A plain copy of a project and its timeline, safe to hand to background AI work.
struct ProjectSnapshot: Sendable {
    struct Day: Sendable {
        var day: String
        var signal: String
        var note: String
        var blockers: [String]
        var nextSteps: [String]
    }

    var name: String
    var details: String
    var status: String
    var start: String
    var lastMentioned: String
    var target: String?
    var overview: String?
    /// Oldest first.
    var days: [Day]

    @MainActor
    init(_ project: Project) {
        name = project.name
        details = project.details
        status = project.status.label
        start = DayFormat.iso(project.startDate)
        lastMentioned = DayFormat.iso(project.lastMentioned)
        target = project.targetDate.map(DayFormat.iso)
        overview = project.insight?.summary
        days = project.timeline.reversed().compactMap { entry in
            guard let note = project.note(in: entry) else { return nil }
            return Day(
                day: DayFormat.iso(entry.date),
                signal: note.signal.rawValue,
                note: note.note,
                blockers: note.blockers,
                nextSteps: note.nextSteps
            )
        }
    }

    /// The project as text for an AI prompt, keeping the most recent `dayLimit` days.
    func promptBlock(dayLimit: Int) -> String {
        var lines = ["<project name=\"\(name)\" status=\"\(status)\" started=\"\(start)\" last_mentioned=\"\(lastMentioned)\">"]
        if !details.isEmpty { lines.append("Description: \(details)") }
        if let target { lines.append("Target date: \(target)") }
        if let overview, !overview.isEmpty { lines.append("Overview so far: \(overview)") }
        let shown = days.suffix(dayLimit)
        if shown.count < days.count { lines.append("(Showing the latest \(shown.count) of \(days.count) days.)") }
        for day in shown {
            var line = "- \(day.day) [\(day.signal)] \(day.note)"
            if !day.blockers.isEmpty { line += " Blockers: " + day.blockers.joined(separator: "; ") + "." }
            if !day.nextSteps.isEmpty { line += " Next: " + day.nextSteps.joined(separator: "; ") + "." }
            lines.append(line)
        }
        lines.append("</project>")
        return lines.joined(separator: "\n")
    }
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
    var projectNotes: [ProjectNote]
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
        projectNotes = entry.projectNotes
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
        if !projectNotes.isEmpty {
            lines.append("Projects: " + projectNotes.map { "\($0.projectName) (\($0.signal.rawValue)): \($0.note)" }.joined(separator: "; "))
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

    /// Reads a YYYY-MM-DD date. Returns nil for empty or malformed text.
    static func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return isoFormatter.date(from: trimmed)
    }

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

    static func dailyPrompt(transcript: String, day: Date, goalTitles: [String], projectNames: [String]) -> String {
        let goals = goalTitles.isEmpty
            ? "(No goals set yet. Leave goalUpdates empty.)"
            : goalTitles.map { "- \($0)" }.joined(separator: "\n")
        let projects = projectNames.isEmpty
            ? "(No projects yet.)"
            : projectNames.map { "- \($0)" }.joined(separator: "\n")
        return """
        Date: \(DayFormat.long(day))

        My current goals:
        \(goals)

        My current projects:
        \(projects)

        My spoken recap:
        \(transcript)

        Today is \(DayFormat.iso(day)).

        Summarize my day.
        - goalUpdates: only goals from my list above, using the exact title, and only ones I \
        actually made progress on today.
        - suggestedGoals: bigger, longer-term goals I said I'm working toward that are NOT in my \
        list (for example "Get AWS certified" or "Get promoted to senior engineer"). Give each a \
        short title (under 8 words) and one sentence on what I did toward it today. Don't include \
        one-off tasks or chores. Leave it empty if there are none.
        - targetDate (on both lists): if I mentioned a deadline or target date for that goal, \
        give it as YYYY-MM-DD. Work out relative dates such as "by the end of March" or "in six \
        weeks" from today's date. Use an empty string if I didn't mention one.
        - projects: ongoing projects I worked on today, meaning work that spans several days, \
        such as "Checkout redesign" or "Kitchen remodel". Never one-off tasks like answering \
        emails, a single meeting, or errands. If the work clearly belongs to one of my current \
        projects above, use that exact name, never a near-duplicate. Otherwise give it a short, \
        specific name (2 to 5 words). For each project: note is what I did on it today in 1 to 2 \
        sentences; status is exactly one of started, progressed, blocked, or completed; blockers \
        and nextSteps are only ones I mentioned (empty if none). Leave projects empty if there are none.
        """
    }

    static let projectInstructions = """
    You keep a running overview of one of the user's projects, written from their daily \
    journal notes about it. Write in the first person ("I"). Use only facts in the notes. \
    Never invent details, numbers, or outcomes. Keep each list item short and specific.
    """

    static func projectPrompt(_ project: ProjectSnapshot, dayLimit: Int) -> String {
        """
        Today's date: \(DayFormat.iso(Date()))

        \(project.promptBlock(dayLimit: dayLimit))

        Write the overview of this project so far:
        - summary: 2 to 4 sentences on what the project is and where it stands now.
        - done: what's been finished.
        - problems: current open problems or blockers.
        - nextSteps: what's next.
        - wins: the key wins worth remembering for a performance review or interview.
        - skills: skills I used on it.
        - blockersSolved: blockers I hit that were later solved, each with how I solved it.
        Leave any list empty if the notes don't support it.
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
    - When entries belong to a project, use that project's timeline to tell its story from \
      start to finish as one STAR answer, instead of stitching together scattered days.
    - If a focus project is named, every story must come from that project.
    """

    static func interviewPrompt(
        request: String,
        context: InterviewContext,
        entryLimit: Int,
        transcriptLimit: Int,
        projectLimit: Int,
        projectDayLimit: Int
    ) -> String {
        let entries = context.entries.prefix(entryLimit)
        let projects = context.projects.prefix(projectLimit)
        var text = """
        The interview I'm preparing for:
        \(request)

        Today's date: \(DayFormat.iso(Date()))

        """
        if let focus = context.focusProject {
            text += "Focus project: use stories only from my project \"\(focus)\".\n\n"
        }
        if !projects.isEmpty {
            text += """
            Projects these entries belong to, each with its full timeline:
            <projects>
            \(projects.map { $0.promptBlock(dayLimit: projectDayLimit) }.joined(separator: "\n\n"))
            </projects>


            """
        }
        text += """
        Here are \(entries.count) of my journal entries (the most relevant ones out of \(context.totalEntries) total):
        <journal_entries>
        \(entries.map { $0.promptBlock(transcriptLimit: transcriptLimit) }.joined(separator: "\n\n"))
        </journal_entries>

        Prepare my interview stories.
        """
        return text
    }
}

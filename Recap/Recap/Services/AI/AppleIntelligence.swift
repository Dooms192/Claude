import Foundation
import FoundationModels

/// Apple Intelligence's on-device model: free, private, works offline.
/// Great for summarizing one day. It can only read a limited amount of text at once,
/// so interview prep with it uses fewer entries than Claude does.
enum AppleIntelligence {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var statusText: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Ready"
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in the Settings app."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still getting ready. Try again later."
        default:
            return "Apple Intelligence isn't available right now."
        }
    }
}

struct AppleSummarizer: RecapSummarizer {
    let displayName = "Apple Intelligence"

    func summarize(transcript: String, day: Date, goalTitles: [String], projectNames: [String]) async throws -> DailySummary {
        let session = LanguageModelSession(instructions: Prompts.dailyInstructions)
        let prompt = Prompts.dailyPrompt(transcript: transcript, day: day, goalTitles: goalTitles, projectNames: projectNames)
        let response = try await session.respond(to: prompt, generating: GeneratedDailySummary.self)
        let output = response.content
        return DailySummary(
            headline: output.headline,
            summary: output.summary,
            accomplishments: output.accomplishments,
            challenges: output.challenges,
            skills: output.skills,
            goalUpdates: output.goalUpdates.map(\.goalUpdate),
            suggestedGoals: output.suggestedGoals.map(\.goalUpdate),
            projects: output.projects.map(\.projectNote)
        )
    }
}

struct AppleCoach: InterviewCoachEngine {
    let displayName = "Apple Intelligence"

    /// The on-device model reads a limited amount of text, so it gets the top few entries,
    /// without transcripts, and at most one short project timeline.
    static let maxEntries = 6

    func prepare(request: String, context: InterviewContext) async throws -> InterviewPrep {
        let session = LanguageModelSession(instructions: Prompts.interviewInstructions)
        let prompt = Prompts.interviewPrompt(
            request: request,
            context: context,
            entryLimit: Self.maxEntries,
            transcriptLimit: 0,
            projectLimit: 1,
            projectDayLimit: 8
        )
        let response = try await session.respond(to: prompt, generating: GeneratedPrep.self)
        let output = response.content
        return InterviewPrep(
            overview: output.overview,
            stories: output.stories.map {
                STARStory(
                    title: $0.title,
                    whyItFits: $0.whyItFits,
                    situation: $0.situation,
                    task: $0.task,
                    action: $0.action,
                    result: $0.result,
                    howToSayIt: $0.howToSayIt,
                    dates: $0.dates
                )
            },
            tips: output.tips
        )
    }
}

/// Writes a project's overview and highlights on the device.
struct AppleProjectWriter {
    /// Recent days only, to fit the on-device model.
    static let dayLimit = 12

    func write(_ project: ProjectSnapshot) async throws -> ProjectInsight {
        let session = LanguageModelSession(instructions: Prompts.projectInstructions)
        let response = try await session.respond(
            to: Prompts.projectPrompt(project, dayLimit: Self.dayLimit),
            generating: GeneratedProjectInsight.self
        )
        let output = response.content
        return ProjectInsight(
            summary: output.summary,
            done: output.done,
            problems: output.problems,
            nextSteps: output.nextSteps,
            wins: output.wins,
            skills: output.skills,
            blockersSolved: output.blockersSolved.map { .init(blocker: $0.blocker, resolution: $0.resolution) }
        )
    }
}

// MARK: - Shapes the on-device model fills in

@Generable
struct GeneratedDailySummary {
    @Guide(description: "A short headline for the day, under 10 words")
    var headline: String

    @Guide(description: "Two to four sentences summarizing the day, written in the first person")
    var summary: String

    @Guide(description: "Concrete things I got done, each one short and specific")
    var accomplishments: [String]

    @Guide(description: "Problems or hard moments, and how I handled them")
    var challenges: [String]

    @Guide(description: "Skills I showed, such as leadership, debugging, communication, or negotiation")
    var skills: [String]

    @Guide(description: "Progress on my listed goals. Only goals I actually worked on today.")
    var goalUpdates: [GeneratedGoalUpdate]

    @Guide(description: "Longer-term goals I said I'm working toward that are NOT in my list. Short title plus one sentence. Empty if none.")
    var suggestedGoals: [GeneratedGoalUpdate]

    @Guide(description: "Ongoing multi-day projects I worked on today. Reuse an exact name from my project list when it fits. No one-off tasks. Empty if none.")
    var projects: [GeneratedProjectNote]
}

@Generable
struct GeneratedProjectNote {
    @Guide(description: "The project name: an exact name from my list if it fits, otherwise a short new name of 2 to 5 words")
    var projectName: String

    @Guide(description: "What I did on it today, in 1 to 2 sentences")
    var note: String

    @Guide(description: "Exactly one of: started, progressed, blocked, completed")
    var status: String

    @Guide(description: "Blockers I mentioned. Empty if none.")
    var blockers: [String]

    @Guide(description: "Next steps I mentioned. Empty if none.")
    var nextSteps: [String]

    var projectNote: ProjectNote {
        ProjectNote(projectName: projectName, note: note, status: status, blockers: blockers, nextSteps: nextSteps)
    }
}

@Generable
struct GeneratedProjectInsight {
    @Guide(description: "2 to 4 sentences on what the project is and where it stands now")
    var summary: String
    @Guide(description: "What's been finished")
    var done: [String]
    @Guide(description: "Current open problems or blockers")
    var problems: [String]
    @Guide(description: "What's next")
    var nextSteps: [String]
    @Guide(description: "Key wins worth remembering for a review or interview")
    var wins: [String]
    @Guide(description: "Skills I used on it")
    var skills: [String]
    @Guide(description: "Blockers that were later solved, each with how")
    var blockersSolved: [GeneratedSolvedBlocker]
}

@Generable
struct GeneratedSolvedBlocker {
    @Guide(description: "The blocker")
    var blocker: String
    @Guide(description: "How I solved it")
    var resolution: String
}

@Generable
struct GeneratedGoalUpdate {
    @Guide(description: "The exact goal title from my list")
    var goalTitle: String

    @Guide(description: "One sentence on what I did toward this goal")
    var note: String

    @Guide(description: "A deadline I mentioned for this goal as YYYY-MM-DD, worked out from today's date. Empty string if none.")
    var targetDate: String

    var goalUpdate: GoalUpdate {
        GoalUpdate(goalTitle: goalTitle, note: note, targetDate: targetDate.isEmpty ? nil : targetDate)
    }
}

@Generable
struct GeneratedPrep {
    @Guide(description: "Two or three sentences on what this interviewer likely wants and which experiences fit best")
    var overview: String

    @Guide(description: "One to three interview stories in STAR format, strongest first")
    var stories: [GeneratedStory]

    @Guide(description: "Three short, practical tips for this interview")
    var tips: [String]
}

@Generable
struct GeneratedStory {
    @Guide(description: "A short title for the story")
    var title: String
    @Guide(description: "One sentence on why this story fits the interview")
    var whyItFits: String
    @Guide(description: "Situation: the context and background")
    var situation: String
    @Guide(description: "Task: what I was responsible for")
    var task: String
    @Guide(description: "Action: the specific steps I took")
    var action: String
    @Guide(description: "Result: the outcome. If not recorded, say what to find out before the interview.")
    var result: String
    @Guide(description: "A natural first-person answer I could say out loud in about a minute")
    var howToSayIt: String
    @Guide(description: "The entry dates this story uses, as YYYY-MM-DD")
    var dates: [String]
}

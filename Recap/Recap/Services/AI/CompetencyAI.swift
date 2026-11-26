import Foundation
import FoundationModels

/// Decides whether Claude or Apple Intelligence does a job, with the same fallback rules
/// as daily summaries.
enum AIRouting {
    /// The Claude key when Claude should do the job, or nil for Apple Intelligence.
    static func claudeKey(preferring engine: AIEngine) throws -> String? {
        let key = AIConfig.claudeKey
        switch engine {
        case .claude:
            if let key { return key }
            if AppleIntelligence.isAvailable { return nil }
        case .apple:
            if AppleIntelligence.isAvailable { return nil }
            if let key { return key }
        }
        throw RecapError.noEngine(AppleIntelligence.statusText)
    }
}

// MARK: - Shared shapes

/// A competency picked for interview prep, with your tagged evidence for it.
struct CompetencyBrief: Sendable {
    struct Evidence: Sendable {
        var day: String
        var strength: String
        var moment: String
    }

    var name: String
    var definition: String
    var signals: [String]
    /// Strongest first.
    var evidence: [Evidence]
    /// What a strong interview answer shows for this competency.
    var listenFor: [String] = []
    /// Ways people fall short, for the story to avoid. Only sent to Claude.
    var lessSkilled: [String] = []

    /// `detailed` adds the less-skilled patterns; it's off for Apple's small on-device model.
    func promptBlock(detailed: Bool = true) -> String {
        var lines = ["<competency name=\"\(name)\">", "Definition: \(definition)", "Behaviors: \(signals.joined(separator: "; "))"]
        if !listenFor.isEmpty {
            lines.append("What interviewers listen for: \(listenFor.joined(separator: "; "))")
        }
        if detailed, !lessSkilled.isEmpty {
            lines.append("Less-skilled patterns the story should avoid: \(lessSkilled.joined(separator: "; "))")
        }
        if evidence.isEmpty {
            lines.append("Tagged evidence: none yet.")
        } else {
            lines.append("Tagged evidence (strongest first):")
            lines += evidence.map { "- \($0.day) [\($0.strength)] \($0.moment)" }
        }
        lines.append("</competency>")
        return lines.joined(separator: "\n")
    }
}

struct CompetencyTagList: Codable, Sendable {
    struct Item: Codable, Sendable {
        var competency: String
        var moment: String
        var strength: String
    }
    var tags: [Item]
}

struct CompetencyPicks: Codable, Sendable {
    var competencies: [String]
}

/// Claude's and Apple's answer in competency mode, turned into a normal `InterviewPrep`.
struct CompetencyPrepPayload: Codable, Sendable {
    struct Story: Codable, Sendable {
        var competency: String
        var title: String
        var whyThisExample: String
        var hasStrongEvidence: Bool
        var situation: String
        var task: String
        var action: String
        var result: String
        var howToSayIt: String
        var dates: [String]
        var followUps: [FollowUp]
        var buildEvidenceTip: String
    }

    var overview: String
    var stories: [Story]
    var tips: [String]

    var prep: InterviewPrep {
        InterviewPrep(
            overview: overview,
            stories: stories.map { story in
                let tip = story.buildEvidenceTip.trimmed
                return STARStory(
                    title: story.title,
                    whyItFits: story.whyThisExample,
                    situation: story.situation,
                    task: story.task,
                    action: story.action,
                    result: story.result,
                    howToSayIt: story.howToSayIt,
                    dates: story.dates,
                    competency: CompetencyLibrary.find(story.competency)?.name ?? story.competency,
                    followUps: story.followUps,
                    gapAdvice: story.hasStrongEvidence || tip.isEmpty ? nil : tip
                )
            },
            tips: tips
        )
    }
}

// MARK: - Prompts

enum CompetencyPrompts {
    static let taggingInstructions = """
    You find leadership competencies in someone's spoken end-of-day recap. Only tag a \
    competency when the recap has real evidence of the person doing it. Never guess or \
    stretch. Most days show 0 to 4 competencies, and an empty list is a fine answer.
    """

    static func taggingPrompt(transcript: String, list: String) -> String {
        """
        Competencies (use these exact names):
        \(list)

        My spoken recap:
        \(transcript)

        Tag the competencies I clearly showed. For each:
        - competency: the exact name from the list.
        - moment: the specific moment that shows it, in one sentence, quoted or closely \
        paraphrased from what I said.
        - strength: strong if I clearly led or drove it, solid if I clearly did it, light if \
        it's only a passing mention.
        """
    }

    static let detectionInstructions = """
    You match interview descriptions and job postings to leadership competencies. Pick \
    only competencies the text mentions or clearly implies. Use the exact names from the list.
    """

    static func detectionPrompt(text: String, isJobPosting: Bool, list: String) -> String {
        let task = isJobPosting
            ? "Pick the 3 to 5 competencies this job posting emphasizes most, most important first."
            : "Pick every competency this description mentions or implies (at most 5), most important first. For example, \"handle ambiguity and lead without authority\" means Manages ambiguity and Persuades. If none apply, return an empty list."
        return """
        Competencies:
        \(list)

        \(isJobPosting ? "Job posting" : "Interview description"):
        \(text)

        \(task)
        """
    }

    static let interviewInstructions = """
    You are an expert interview coach. You build one STAR story (Situation, Task, Action, \
    Result) for each competency the user asks for, using only facts from their own journal \
    entries.

    Rules:
    - For each competency, choose the best example: prefer days tagged with that competency \
      at "strong", and complete stories with a clear result.
    - When the example is part of a project, use the project's timeline so the story runs \
      from start to finish.
    - The Action must clearly show the behaviors of that competency, and what interviewers \
      listen for in it. Show it through what the user did; don't name the competency \
      awkwardly. When less-skilled patterns are listed, make sure the story doesn't show them.
    - Don't reuse the same example for two competencies when another good one exists.
    - competency is the exact competency name. whyThisExample is one sentence on why you \
      chose this example.
    - If there's no good evidence for a competency, set hasStrongEvidence to false, still \
      tell the closest example as the story, say plainly in whyThisExample that it's a \
      stretch, and in buildEvidenceTip say what to look for or do in daily work to build a \
      real example. Otherwise set hasStrongEvidence to true and leave buildEvidenceTip empty.
    - followUps: 2 to 3 likely follow-up questions an interviewer might ask about this \
      competency, each with short notes on how to answer from the user's real experience.
    - Never invent numbers, names, or outcomes. If a result isn't recorded, say so in the \
      result and suggest what to find out before the interview.
    - howToSayIt is a natural first-person answer to say out loud in 60 to 90 seconds.
    - dates lists the entry dates (YYYY-MM-DD) each story draws on.
    - Give one story per requested competency, in the order given, plus 3 to 5 short tips.
    """

    static func interviewPrompt(
        request: String,
        context: InterviewContext,
        entryLimit: Int,
        transcriptLimit: Int,
        projectLimit: Int,
        projectDayLimit: Int,
        detailedCompetencies: Bool
    ) -> String {
        let description = request.trimmed.isEmpty ? "A general interview focused on these competencies." : request
        var text = """
        The interview I'm preparing for:
        \(description)

        Today's date: \(DayFormat.iso(Date()))

        Build one story for each of these competencies:
        \(context.competencies.map { $0.promptBlock(detailed: detailedCompetencies) }.joined(separator: "\n\n"))


        """
        if let focus = context.focusProject {
            text += "Focus project: use stories only from my project \"\(focus)\".\n\n"
        }
        let projects = context.projects.prefix(projectLimit)
        if !projects.isEmpty {
            text += "Projects these entries belong to, each with its full timeline:\n<projects>\n"
            text += projects.map { $0.promptBlock(dayLimit: projectDayLimit) }.joined(separator: "\n\n")
            text += "\n</projects>\n\n"
        }
        let entries = context.entries.prefix(entryLimit)
        text += "My journal entries (\(entries.count) chosen out of \(context.totalEntries)):\n<journal_entries>\n"
        text += entries.map { $0.promptBlock(transcriptLimit: transcriptLimit) }.joined(separator: "\n\n")
        text += "\n</journal_entries>\n\nBuild my competency stories."
        return text
    }
}

// MARK: - Tagging recaps

/// Tags each recap with the competencies it shows.
@MainActor
enum CompetencyTagging {
    /// How many AI tags a single day can get.
    static let maxTagsPerDay = 6

    /// Tags one recap. Tags you added by hand are kept.
    static func tag(_ entry: DayEntry) async throws {
        let transcript = entry.transcript.trimmed
        guard !transcript.isEmpty else { return }

        let items: [CompetencyTagList.Item]
        if let key = try AIRouting.claudeKey(preferring: AIConfig.summaryEngine) {
            items = try await ClaudeClient(apiKey: key).structured(
                CompetencyTagList.self,
                system: CompetencyPrompts.taggingInstructions,
                prompt: CompetencyPrompts.taggingPrompt(transcript: transcript, list: CompetencyLibrary.fullList),
                schema: JSONSchema.object([
                    "tags": JSONSchema.array(
                        JSONSchema.object([
                            "competency": JSONSchema.oneOf(CompetencyLibrary.all.map(\.name), "The exact competency name"),
                            "moment": JSONSchema.string("The moment that shows it, in one sentence, close to what I said"),
                            "strength": JSONSchema.oneOf(["strong", "solid", "light"], "How clearly I showed it"),
                        ]),
                        "Competencies with real evidence in the recap. Usually 0 to 4. Empty if none."
                    ),
                ])
            ).tags
        } else {
            // A separate, small call, so the on-device model isn't overloaded by the main summary.
            let session = LanguageModelSession(instructions: CompetencyPrompts.taggingInstructions)
            let response = try await session.respond(
                to: CompetencyPrompts.taggingPrompt(transcript: transcript, list: CompetencyLibrary.compactList),
                generating: GeneratedCompetencyTags.self
            )
            items = response.content.tags.map {
                CompetencyTagList.Item(competency: $0.competency, moment: $0.moment, strength: $0.strength)
            }
        }

        var tags = entry.competencyTags.filter(\.isManual)
        var added = 0
        for item in items where added < maxTagsPerDay {
            guard let competency = CompetencyLibrary.find(item.competency),
                  !item.moment.trimmed.isEmpty,
                  !tags.contains(where: { $0.competency == competency.name })
            else { continue }
            tags.append(CompetencyTag(
                competency: competency.name,
                moment: item.moment.trimmed,
                strength: CompetencyStrength(loose: item.strength).rawValue,
                isManual: false
            ))
            added += 1
        }
        entry.competencyTags = tags
        entry.competenciesTaggedAt = Date()
    }

    /// Tags recaps recorded before competency tagging existed. Returns how many failed.
    static func tagUntagged(_ entries: [DayEntry], progress: (Int, Int) -> Void) async -> Int {
        let pending = entries.filter { $0.competenciesTaggedAt == nil && !$0.transcript.trimmed.isEmpty }
        var failures = 0
        for (index, entry) in pending.enumerated() {
            progress(index, pending.count)
            do {
                try await tag(entry)
                try? entry.modelContext?.save()
            } catch {
                failures += 1
            }
        }
        progress(pending.count, pending.count)
        return failures
    }
}

// MARK: - Detecting competencies in text

@MainActor
enum CompetencyDetection {
    /// Competencies a description mentions or implies, or the 3 to 5 a job posting emphasizes.
    static func detect(in text: String, isJobPosting: Bool) async throws -> [String] {
        let text = text.trimmed
        guard !text.isEmpty else { return [] }

        let names: [String]
        if let key = try AIRouting.claudeKey(preferring: AIConfig.interviewEngine) {
            names = try await ClaudeClient(apiKey: key).structured(
                CompetencyPicks.self,
                system: CompetencyPrompts.detectionInstructions,
                prompt: CompetencyPrompts.detectionPrompt(
                    text: String(text.prefix(20000)),
                    isJobPosting: isJobPosting,
                    list: CompetencyLibrary.fullList
                ),
                schema: JSONSchema.object([
                    "competencies": JSONSchema.array(
                        JSONSchema.oneOf(CompetencyLibrary.all.map(\.name), "An exact competency name"),
                        "Matching competencies, most important first"
                    ),
                ])
            ).competencies
        } else {
            let session = LanguageModelSession(instructions: CompetencyPrompts.detectionInstructions)
            let response = try await session.respond(
                to: CompetencyPrompts.detectionPrompt(
                    text: String(text.prefix(2500)),
                    isJobPosting: isJobPosting,
                    list: CompetencyLibrary.compactList
                ),
                generating: GeneratedCompetencyPicks.self
            )
            names = response.content.competencies
        }

        var seen = Set<String>()
        return names
            .compactMap { CompetencyLibrary.find($0)?.name }
            .filter { seen.insert($0).inserted }
            .prefix(5)
            .map { $0 }
    }
}

// MARK: - One story per competency

extension ClaudeCoach {
    func prepareCompetencies(request: String, context: InterviewContext) async throws -> InterviewPrep {
        let storySchema = JSONSchema.object([
            "competency": JSONSchema.string("The exact competency name"),
            "title": JSONSchema.string("A short title for the story"),
            "whyThisExample": JSONSchema.string("One sentence on why this example was chosen"),
            "hasStrongEvidence": JSONSchema.boolean("False when there's no good example and this is the closest stretch"),
            "situation": JSONSchema.string("Situation: the context and background"),
            "task": JSONSchema.string("Task: what I was responsible for"),
            "action": JSONSchema.string("Action: the steps I took, clearly showing the competency's behaviors"),
            "result": JSONSchema.string("Result: the outcome, or what to find out if it isn't recorded"),
            "howToSayIt": JSONSchema.string("A natural first-person answer to say out loud in 60 to 90 seconds"),
            "dates": JSONSchema.strings("Entry dates this story draws on, as YYYY-MM-DD"),
            "followUps": JSONSchema.array(
                JSONSchema.object([
                    "question": JSONSchema.string("A likely follow-up question about this competency"),
                    "howToAnswer": JSONSchema.string("Short notes on answering it from my real experience"),
                ]),
                "Two to three likely follow-up questions"
            ),
            "buildEvidenceTip": JSONSchema.string("When evidence is weak: what to look for or do to build a real example. Otherwise empty."),
        ])
        return try await client.structured(
            CompetencyPrepPayload.self,
            system: CompetencyPrompts.interviewInstructions,
            prompt: CompetencyPrompts.interviewPrompt(
                request: request,
                context: context,
                entryLimit: Self.maxEntries,
                transcriptLimit: 1200,
                projectLimit: 5,
                projectDayLimit: 40,
                detailedCompetencies: true
            ),
            schema: JSONSchema.object([
                "overview": JSONSchema.string("Two or three sentences on how these competencies fit this interview"),
                "stories": JSONSchema.array(storySchema, "One story per requested competency, in order"),
                "tips": JSONSchema.strings("Three to five short, practical tips"),
            ])
        ).prep
    }
}

extension AppleCoach {
    /// The on-device model handles up to this many competencies per request.
    static let maxCompetencies = 3

    func prepareCompetencies(request: String, context: InterviewContext) async throws -> InterviewPrep {
        let session = LanguageModelSession(instructions: CompetencyPrompts.interviewInstructions)
        let response = try await session.respond(
            to: CompetencyPrompts.interviewPrompt(
                request: request,
                context: context,
                entryLimit: Self.maxEntries,
                transcriptLimit: 0,
                projectLimit: 1,
                projectDayLimit: 6,
                detailedCompetencies: false
            ),
            generating: GeneratedCompetencyPrep.self
        )
        let output = response.content
        return CompetencyPrepPayload(
            overview: output.overview,
            stories: output.stories.map {
                CompetencyPrepPayload.Story(
                    competency: $0.competency,
                    title: $0.title,
                    whyThisExample: $0.whyThisExample,
                    hasStrongEvidence: $0.hasStrongEvidence,
                    situation: $0.situation,
                    task: $0.task,
                    action: $0.action,
                    result: $0.result,
                    howToSayIt: $0.howToSayIt,
                    dates: $0.dates,
                    followUps: $0.followUps.map { FollowUp(question: $0.question, howToAnswer: $0.howToAnswer) },
                    buildEvidenceTip: $0.buildEvidenceTip
                )
            },
            tips: output.tips
        ).prep
    }
}

// MARK: - Shapes the on-device model fills in

@Generable
struct GeneratedCompetencyTags {
    @Guide(description: "Competencies with real evidence in the recap. Usually 0 to 4. Empty if none.")
    var tags: [GeneratedCompetencyTag]
}

@Generable
struct GeneratedCompetencyTag {
    @Guide(description: "The exact competency name from the list")
    var competency: String
    @Guide(description: "The moment that shows it, in one sentence, close to what I said")
    var moment: String
    @Guide(description: "Exactly one of: strong, solid, light")
    var strength: String
}

@Generable
struct GeneratedCompetencyPicks {
    @Guide(description: "Exact competency names from the list, most important first. At most 5.")
    var competencies: [String]
}

@Generable
struct GeneratedCompetencyPrep {
    @Guide(description: "Two or three sentences on how these competencies fit this interview")
    var overview: String
    @Guide(description: "One story per requested competency, in order")
    var stories: [GeneratedCompetencyStory]
    @Guide(description: "Three short, practical tips")
    var tips: [String]
}

@Generable
struct GeneratedCompetencyStory {
    @Guide(description: "The exact competency name")
    var competency: String
    @Guide(description: "A short title for the story")
    var title: String
    @Guide(description: "One sentence on why this example was chosen")
    var whyThisExample: String
    @Guide(description: "False when there's no good example and this is a stretch")
    var hasStrongEvidence: Bool
    @Guide(description: "Situation: the context")
    var situation: String
    @Guide(description: "Task: what I was responsible for")
    var task: String
    @Guide(description: "Action: the steps I took, showing the competency")
    var action: String
    @Guide(description: "Result: the outcome")
    var result: String
    @Guide(description: "A natural first-person answer to say out loud in about a minute")
    var howToSayIt: String
    @Guide(description: "Entry dates used, as YYYY-MM-DD")
    var dates: [String]
    @Guide(description: "Two likely follow-up questions with how to answer")
    var followUps: [GeneratedFollowUp]
    @Guide(description: "If evidence is weak, what to do to build a real example. Otherwise empty.")
    var buildEvidenceTip: String
}

@Generable
struct GeneratedFollowUp {
    @Guide(description: "A likely follow-up question")
    var question: String
    @Guide(description: "Short notes on how to answer it")
    var howToAnswer: String
}

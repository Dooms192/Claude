import Foundation
import SwiftData
import NaturalLanguage

enum RecapError: LocalizedError {
    case emptyTranscript
    case noEngine(String)
    case noEntries
    case noProjectEntries(String)

    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return "There's nothing to summarize yet. Record your recap first."
        case .noEngine(let reason):
            return "No AI is available to do this. \(reason) Or add a Claude API key in Settings."
        case .noEntries:
            return "You don't have any recaps yet. Record a few days first, then come back to prep."
        case .noProjectEntries(let name):
            return "No recaps mention \"\(name)\" yet."
        }
    }
}

/// Picks an AI and summarizes a day. The recap is always saved first, so a failed
/// summary never loses what you said; you can retry from the journal.
@MainActor
enum RecapProcessor {
    static func summarize(_ entry: DayEntry, goals: [Goal]) async throws {
        let transcript = entry.transcript.trimmed
        guard !transcript.isEmpty else { throw RecapError.emptyTranscript }

        let summarizer = try pickSummarizer()
        let activeGoals = goals.filter { !$0.isArchived }
        let allProjects = (try? entry.modelContext?.fetch(FetchDescriptor<Project>())) ?? []
        let result = try await summarizer.summarize(
            transcript: transcript,
            day: entry.date,
            goalTitles: activeGoals.map(\.title),
            projectNames: projectNamesForPrompt(allProjects, claude: summarizer is ClaudeSummarizer)
        )
        entry.apply(result, engine: summarizer.displayName, goals: activeGoals)
        entry.applyProjects(result.projects, existing: allProjects)

        // Competency tags come from a second, separate call. A failure here never fails
        // the recap; you can re-tag later from the Competencies screen.
        try? await CompetencyTagging.tag(entry)

        // Refresh the overview of every project this recap touched, in the background.
        let touched = entry.projects ?? []
        if !touched.isEmpty {
            Task { await ProjectInsights.refreshQuietly(touched) }
        }
    }

    /// Existing project names the AI should reuse. Apple's on-device model is small, so it
    /// only gets your active projects; Claude also gets paused and inactive ones.
    private static func projectNamesForPrompt(_ projects: [Project], claude: Bool) -> [String] {
        let eligible = projects
            .filter { claude ? $0.status != .completed : $0.status == .active }
            .sorted { $0.lastMentioned > $1.lastMentioned }
        return eligible.prefix(claude ? 40 : 12).map(\.name)
    }

    /// Uses your chosen engine, and falls back to the other one if it can't run.
    static func pickSummarizer() throws -> any RecapSummarizer {
        let key = AIConfig.claudeKey
        switch AIConfig.summaryEngine {
        case .claude:
            if let key { return ClaudeSummarizer(apiKey: key) }
            if AppleIntelligence.isAvailable { return AppleSummarizer() }
        case .apple:
            if AppleIntelligence.isAvailable { return AppleSummarizer() }
            if let key { return ClaudeSummarizer(apiKey: key) }
        }
        throw RecapError.noEngine(AppleIntelligence.statusText)
    }
}

/// Finds the right days in your journal and turns them into STAR interview stories.
@MainActor
enum InterviewCoach {
    struct Outcome {
        var prep: InterviewPrep
        var engine: String
        var note: String?
        var entriesUsed: Int
    }

    /// With `project`, stories come only from that project's days. With `competencies`,
    /// you get one story per competency.
    static func prepare(
        for request: String,
        entries: [DayEntry],
        project: Project? = nil,
        competencies: [String] = []
    ) async throws -> Outcome {
        let pool = project.map { $0.entries ?? [] } ?? entries
        let usable = pool.filter { !$0.transcript.trimmed.isEmpty }
        guard !usable.isEmpty else {
            if let project { throw RecapError.noProjectEntries(project.name) }
            throw RecapError.noEntries
        }

        let key = AIConfig.claudeKey
        let wantsClaude = AIConfig.interviewEngine == .claude

        let coach: any InterviewCoachEngine
        let limit: Int
        var note: String?
        if let key, wantsClaude || !AppleIntelligence.isAvailable {
            coach = ClaudeCoach(apiKey: key)
            limit = ClaudeCoach.maxEntries
        } else if AppleIntelligence.isAvailable {
            coach = AppleCoach()
            limit = AppleCoach.maxEntries
            if wantsClaude {
                note = "Made with Apple Intelligence, which can only read your \(limit) most relevant days. Add a Claude API key in Settings for deeper stories drawn from more of your history."
            }
        } else {
            throw RecapError.noEngine(AppleIntelligence.statusText)
        }

        if !competencies.isEmpty {
            return try await prepareCompetencies(
                request: request, usable: usable, project: project, names: competencies,
                coach: coach, limit: limit, note: note
            )
        }

        let picked = EntrySearch.rank(usable, for: request, limit: limit)
        let context = InterviewContext(
            entries: picked.map { EntrySnapshot($0) },
            totalEntries: usable.count,
            projects: projectsFor(picked, focus: project).map { ProjectSnapshot($0) },
            focusProject: project?.name
        )
        let prep = try await coach.prepare(request: request, context: context)
        return Outcome(prep: prep, engine: coach.displayName, note: note, entriesUsed: picked.count)
    }

    /// Competency mode: picks the best tagged days for each competency (strong, complete
    /// stories first), fills in with the closest matches, and asks for one story each.
    private static func prepareCompetencies(
        request: String,
        usable: [DayEntry],
        project: Project?,
        names: [String],
        coach: any InterviewCoachEngine,
        limit: Int,
        note: String?
    ) async throws -> Outcome {
        let isClaude = coach is ClaudeCoach
        let all = names.compactMap { CompetencyLibrary.find($0) }
        let chosen = Array(all.prefix(isClaude ? 8 : AppleCoach.maxCompetencies))
        var note = note
        if chosen.count < all.count {
            let skipped = all.dropFirst(chosen.count).map(\.name).joined(separator: ", ")
            note = [note, "Apple Intelligence can handle \(chosen.count) competencies at a time, so these were left out: \(skipped). Add a Claude API key in Settings to do them all at once."]
                .compactMap { $0 }
                .joined(separator: " ")
        }

        var picked: [DayEntry] = []
        var briefs: [CompetencyBrief] = []
        for competency in chosen {
            let evidence = usable
                .flatMap { entry in
                    entry.competencyTags
                        .filter { CompetencyLibrary.find($0.competency)?.name == competency.name }
                        .map { (entry: entry, tag: $0) }
                }
                .sorted { a, b in
                    if a.tag.level != b.tag.level { return a.tag.level > b.tag.level }
                    // Prefer complete stories: days with recorded accomplishments.
                    if a.entry.accomplishments.isEmpty != b.entry.accomplishments.isEmpty {
                        return !a.entry.accomplishments.isEmpty
                    }
                    return a.entry.date > b.entry.date
                }
            briefs.append(CompetencyBrief(
                name: competency.name,
                definition: competency.definition,
                signals: competency.signals,
                evidence: evidence.prefix(isClaude ? 8 : 3).map {
                    CompetencyBrief.Evidence(day: DayFormat.iso($0.entry.date), strength: $0.tag.level.rawValue, moment: $0.tag.moment)
                }
            ))
            for item in evidence.prefix(isClaude ? 4 : 2) where !picked.contains(where: { $0.id == item.entry.id }) {
                picked.append(item.entry)
            }
        }

        // Fill in with the days closest in meaning, which also gives the coach a "closest
        // example" for competencies with no tagged evidence.
        let fillQuery = ([request] + chosen.map { "\($0.name): \($0.signals.joined(separator: ", "))" }).joined(separator: " ")
        for entry in EntrySearch.rank(usable, for: fillQuery, limit: isClaude ? 10 : 3)
        where !picked.contains(where: { $0.id == entry.id }) {
            picked.append(entry)
        }
        picked = Array(picked.prefix(limit))

        let context = InterviewContext(
            entries: picked.map { EntrySnapshot($0) },
            totalEntries: usable.count,
            projects: projectsFor(picked, focus: project).map { ProjectSnapshot($0) },
            focusProject: project?.name,
            competencies: briefs
        )
        let prep = try await coach.prepareCompetencies(request: request, context: context)
        return Outcome(prep: prep, engine: coach.displayName, note: note, entriesUsed: picked.count)
    }

    /// The projects behind the chosen entries, most represented first, so the coach can
    /// tell each project's story from its full timeline.
    private static func projectsFor(_ entries: [DayEntry], focus: Project?) -> [Project] {
        if let focus { return [focus] }
        var counts: [UUID: (project: Project, count: Int)] = [:]
        for entry in entries {
            for project in entry.projects ?? [] {
                counts[project.id, default: (project: project, count: 0)].count += 1
            }
        }
        return counts.values.sorted { $0.count > $1.count }.map { $0.project }
    }
}

/// Writes and refreshes each project's AI overview, using the same engine choice as daily
/// summaries: Apple Intelligence by default, or Claude if you picked it.
@MainActor
enum ProjectInsights {
    static func refresh(_ project: Project) async throws {
        let snapshot = ProjectSnapshot(project)
        guard !snapshot.days.isEmpty else { return }
        let insight: ProjectInsight
        let key = AIConfig.claudeKey
        let useClaude = AIConfig.summaryEngine == .claude ? key != nil : (!AppleIntelligence.isAvailable && key != nil)
        if useClaude, let key {
            insight = try await ClaudeProjectWriter(apiKey: key).write(snapshot)
        } else if AppleIntelligence.isAvailable {
            insight = try await AppleProjectWriter().write(snapshot)
        } else {
            throw RecapError.noEngine(AppleIntelligence.statusText)
        }
        project.setInsight(insight)
        try? project.modelContext?.save()
    }

    /// Refreshes several projects, ignoring failures; you can always refresh by hand.
    static func refreshQuietly(_ projects: [Project]) async {
        for project in projects {
            try? await refresh(project)
        }
    }
}

/// On-device search that matches by meaning, not just exact words.
/// "conflict with a coworker" finds a day where you said "disagreed with my manager".
@MainActor
enum EntrySearch {
    /// The most relevant entries for `query`, best first.
    static func rank(_ entries: [DayEntry], for query: String, limit: Int) -> [DayEntry] {
        let queryWords = keywords(in: query)
        let embedding = NLEmbedding.sentenceEmbedding(for: .english)

        let scored = entries.map { entry -> (entry: DayEntry, score: Double) in
            let text = entry.isSummarized
                ? ([entry.headline, entry.summary] + entry.accomplishments + entry.challenges + entry.skills).joined(separator: ". ")
                : entry.transcript
            var score = 0.0
            if let embedding {
                // Cosine distance runs 0 (same meaning) to 2 (opposite).
                let distance = embedding.distance(between: query, and: String(text.prefix(2000)), distanceType: .cosine)
                score += 0.7 * max(0, 1 - distance / 2)
            }
            if !queryWords.isEmpty {
                let haystack = entry.searchableText.lowercased()
                let hits = queryWords.filter { haystack.contains($0) }.count
                score += (embedding == nil ? 1.0 : 0.3) * Double(hits) / Double(queryWords.count)
            }
            return (entry, score)
        }

        return scored
            .sorted { $0.score == $1.score ? $0.entry.date > $1.entry.date : $0.score > $1.score }
            .prefix(limit)
            .map { $0.entry }
    }

    /// Simple text filter for the journal's search bar.
    static func filter(_ entries: [DayEntry], text: String) -> [DayEntry] {
        let words = text.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            let haystack = entry.searchableText.lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "you", "your", "are", "was", "were", "have",
        "has", "had", "about", "from", "they", "them", "what", "when", "where", "which", "who",
        "how", "into", "out", "time", "tell", "interview", "role", "job", "position", "company",
    ]

    private static func keywords(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = text[range].lowercased()
            if word.count > 2, !stopWords.contains(word), !words.contains(word) { words.append(word) }
            return true
        }
        return words
    }
}

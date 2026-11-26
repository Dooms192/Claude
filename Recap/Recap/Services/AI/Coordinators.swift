import Foundation
import NaturalLanguage

enum RecapError: LocalizedError {
    case emptyTranscript
    case noEngine(String)
    case noEntries

    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return "There's nothing to summarize yet. Record your recap first."
        case .noEngine(let reason):
            return "No AI is available to do this. \(reason) Or add a Claude API key in Settings."
        case .noEntries:
            return "You don't have any recaps yet. Record a few days first, then come back to prep."
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
        let result = try await summarizer.summarize(
            transcript: transcript,
            day: entry.date,
            goalTitles: activeGoals.map(\.title)
        )
        entry.apply(result, engine: summarizer.displayName, goals: activeGoals)
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

    static func prepare(for request: String, entries: [DayEntry]) async throws -> Outcome {
        let usable = entries.filter { !$0.transcript.trimmed.isEmpty }
        guard !usable.isEmpty else { throw RecapError.noEntries }

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

        let picked = EntrySearch.rank(usable, for: request, limit: limit)
        let snapshots = picked.map { EntrySnapshot($0) }
        let prep = try await coach.prepare(request: request, entries: snapshots, totalEntries: usable.count)
        return Outcome(prep: prep, engine: coach.displayName, note: note, entriesUsed: picked.count)
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

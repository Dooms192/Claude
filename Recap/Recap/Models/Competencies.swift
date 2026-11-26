import Foundation
import NaturalLanguage
import SwiftUI

// The competency list, based on the Korn Ferry Leadership Architect competencies from
// "FYI: For Your Improvement". The definitions, signals, keywords, and nudges are written
// in plain words for this app, not copied from the book.
//
// To match your edition of the book, edit `CompetencyLibrary.all` below. Each recap stores
// competency *names*, so if you rename one, older tags under the old name stop matching.

/// The four groups the competencies are organized into.
enum CompetencyFactor: String, CaseIterable, Codable, Identifiable {
    case thought, results, people, personal

    var id: Self { self }

    var label: String {
        switch self {
        case .thought: "Thought"
        case .results: "Results"
        case .people: "People"
        case .personal: "Self"
        }
    }

    var systemImage: String {
        switch self {
        case .thought: "brain.head.profile"
        case .results: "flag.checkered"
        case .people: "person.3.fill"
        case .personal: "figure.mind.and.body"
        }
    }

    var tint: Color {
        switch self {
        case .thought: .indigo
        case .results: .orange
        case .people: .teal
        case .personal: .pink
        }
    }
}

struct Competency: Identifiable, Hashable, Sendable {
    let name: String
    let factor: CompetencyFactor
    /// One plain sentence on what it means.
    let definition: String
    /// Behaviors the AI looks for in a recap.
    let signals: [String]
    /// A few short words for Apple's small on-device model.
    let keywords: String
    /// A question for the recorder's rotating nudge.
    let nudge: String

    var id: String { name }
}

/// How clearly a recap shows a competency.
enum CompetencyStrength: String, CaseIterable, Codable, Identifiable, Comparable {
    case strong, solid, light

    var id: Self { self }

    init(loose text: String) {
        self = CompetencyStrength(rawValue: text.normalizedKey) ?? .solid
    }

    var rank: Int {
        switch self {
        case .strong: 3
        case .solid: 2
        case .light: 1
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    var label: String { rawValue.capitalized }

    var detail: String {
        switch self {
        case .strong: "I clearly led or drove it"
        case .solid: "I clearly did it"
        case .light: "A passing mention"
        }
    }

    var systemImage: String {
        switch self {
        case .strong: "star.fill"
        case .solid: "star.leadinghalf.filled"
        case .light: "star"
        }
    }

    var tint: Color {
        switch self {
        case .strong: .orange
        case .solid: .blue
        case .light: .secondary
        }
    }
}

/// One competency shown in one day's recap, stored on the `DayEntry`.
struct CompetencyTag: Codable, Hashable, Sendable {
    /// The exact competency name from `CompetencyLibrary`.
    var competency: String
    /// The moment that shows it, close to what you said.
    var moment: String
    /// strong, solid, or light.
    var strength: String
    /// True when you added it by hand. Re-tagging keeps manual tags.
    var isManual: Bool

    var level: CompetencyStrength { CompetencyStrength(loose: strength) }
    var definition: Competency? { CompetencyLibrary.find(competency) }
}

enum CompetencyLibrary {
    static let all: [Competency] = [
        // MARK: Thought
        Competency(
            name: "Business insight", factor: .thought,
            definition: "Uses an understanding of how the business and its industry work to make better decisions.",
            signals: ["connected my work to how the business makes money", "used knowledge of the market or competitors", "spotted an industry trend that affects us"],
            keywords: "business model, market, competitors, industry",
            nudge: "Did you connect your work to the bigger business picture today?"
        ),
        Competency(
            name: "Customer focus", factor: .thought,
            definition: "Builds strong customer relationships and shapes solutions around what customers need.",
            signals: ["listened to a customer or user", "changed a plan because of customer feedback", "went out of my way to solve a customer's problem"],
            keywords: "customer, user, client, feedback",
            nudge: "Did you do something for a customer or user today?"
        ),
        Competency(
            name: "Financial acumen", factor: .thought,
            definition: "Understands the numbers, budgets, and financial impact of decisions.",
            signals: ["worked with a budget, cost, or forecast", "weighed the cost or return of an option", "saved money or found new revenue"],
            keywords: "budget, cost, revenue, ROI",
            nudge: "Did money, costs, or budgets come up in your work today?"
        ),
        Competency(
            name: "Tech savvy", factor: .thought,
            definition: "Picks up and uses technology to work smarter and get better results.",
            signals: ["learned or adopted a new tool", "automated something", "used technology to solve a problem faster"],
            keywords: "tool, software, automate, technology",
            nudge: "Did you try a new tool or automate anything today?"
        ),
        Competency(
            name: "Manages complexity", factor: .thought,
            definition: "Makes sense of messy, high-volume, or conflicting information to solve problems.",
            signals: ["broke a messy problem into parts", "pulled together information from many sources", "found the root cause of a problem"],
            keywords: "complex, root cause, analyze, untangle",
            nudge: "Did you untangle a complicated problem today?"
        ),
        Competency(
            name: "Decision quality", factor: .thought,
            definition: "Makes sound, timely decisions that keep things moving.",
            signals: ["made a call with incomplete information", "weighed options and chose one", "made a decision that unblocked others"],
            keywords: "decided, tradeoff, judgment call",
            nudge: "Did you have to make a tough call today?"
        ),
        Competency(
            name: "Balances stakeholders", factor: .thought,
            definition: "Weighs the needs of different groups and finds outcomes that work for them.",
            signals: ["handled competing requests from different groups", "kept several stakeholders informed and aligned", "negotiated a tradeoff between teams"],
            keywords: "stakeholders, competing needs, tradeoff",
            nudge: "Did you juggle what different people or teams wanted today?"
        ),
        Competency(
            name: "Global perspective", factor: .thought,
            definition: "Takes a broad view, thinking about different regions, cultures, and markets.",
            signals: ["worked with people in other countries or time zones", "adapted something for another market or culture", "thought about the global impact of a decision"],
            keywords: "global, international, culture, region",
            nudge: "Did you work across countries, cultures, or markets today?"
        ),
        Competency(
            name: "Cultivates innovation", factor: .thought,
            definition: "Comes up with new and better ways of doing things and helps them take hold.",
            signals: ["proposed a new idea", "ran an experiment or built a prototype", "challenged the usual way of doing something"],
            keywords: "new idea, experiment, prototype, creative",
            nudge: "Did you try a new idea or a different way of doing something today?"
        ),
        Competency(
            name: "Strategic mindset", factor: .thought,
            definition: "Looks ahead to future possibilities and turns them into plans.",
            signals: ["thought about long-term direction", "shaped a roadmap or strategy", "anticipated a future risk or opportunity"],
            keywords: "strategy, roadmap, long term, vision",
            nudge: "Did you think about where things are headed long term today?"
        ),

        // MARK: Results
        Competency(
            name: "Action oriented", factor: .results,
            definition: "Takes on new opportunities and tough challenges with energy and urgency.",
            signals: ["jumped on a problem right away", "volunteered for something", "moved quickly without waiting to be told"],
            keywords: "urgency, initiative, jumped in, volunteered",
            nudge: "Did you jump on something without waiting to be asked today?"
        ),
        Competency(
            name: "Resourcefulness", factor: .results,
            definition: "Gets the most out of limited time, money, and people.",
            signals: ["found a workaround", "did more with less", "reused something that already existed to save effort"],
            keywords: "workaround, limited resources, scrappy",
            nudge: "Did you find a clever workaround today?"
        ),
        Competency(
            name: "Directs work", factor: .results,
            definition: "Gives clear direction, delegates well, and removes obstacles for others.",
            signals: ["delegated a task", "set clear expectations for someone", "unblocked a teammate"],
            keywords: "delegate, direction, assign, unblock",
            nudge: "Did you give someone clear direction or unblock them today?"
        ),
        Competency(
            name: "Plans and aligns", factor: .results,
            definition: "Plans and prioritizes work so it meets goals and fits with what others are doing.",
            signals: ["made a plan or timeline", "prioritized competing work", "coordinated dependencies with another team"],
            keywords: "plan, prioritize, timeline, coordinate",
            nudge: "Did you plan or prioritize work for yourself or others today?"
        ),
        Competency(
            name: "Optimizes work processes", factor: .results,
            definition: "Finds the most effective ways to get work done and keeps improving them.",
            signals: ["improved a process or workflow", "removed a step or bottleneck", "measured and tuned how work gets done"],
            keywords: "process, workflow, efficiency, bottleneck",
            nudge: "Did you make a process faster or smoother today?"
        ),
        Competency(
            name: "Ensures accountability", factor: .results,
            definition: "Holds themselves and others responsible for commitments.",
            signals: ["followed up on a commitment", "owned a mistake", "tracked progress against a goal"],
            keywords: "follow up, ownership, commitments",
            nudge: "Did you follow up on a commitment or own a mistake today?"
        ),
        Competency(
            name: "Drives results", factor: .results,
            definition: "Delivers consistently, even when things get hard.",
            signals: ["shipped or finished something important", "hit a deadline or target", "pushed through an obstacle to deliver"],
            keywords: "delivered, shipped, deadline, target",
            nudge: "What did you deliver or finish today?"
        ),

        // MARK: People
        Competency(
            name: "Collaborates", factor: .people,
            definition: "Builds partnerships and works with others toward shared goals.",
            signals: ["worked closely with another person or team", "shared information or credit", "helped someone else succeed"],
            keywords: "teamwork, partnered, together, shared",
            nudge: "Who did you team up with today?"
        ),
        Competency(
            name: "Manages conflict", factor: .people,
            definition: "Handles disagreements constructively and finds common ground.",
            signals: ["addressed a disagreement directly", "found common ground", "calmed a tense situation"],
            keywords: "disagreement, conflict, common ground, tension",
            nudge: "Did you work through a disagreement today?"
        ),
        Competency(
            name: "Interpersonal savvy", factor: .people,
            definition: "Relates comfortably with all kinds of people and reads situations well.",
            signals: ["read the room and adjusted my approach", "built rapport with someone new", "handled a sensitive conversation with tact"],
            keywords: "rapport, read the room, tact, relationships",
            nudge: "Did you handle a delicate conversation today?"
        ),
        Competency(
            name: "Builds networks", factor: .people,
            definition: "Builds relationships inside and outside the organization and uses them to get things done.",
            signals: ["met or reached out to someone new", "used a contact to get something done", "kept in touch with my network"],
            keywords: "network, contacts, connections, reached out",
            nudge: "Did you meet someone new or lean on a contact today?"
        ),
        Competency(
            name: "Attracts top talent", factor: .people,
            definition: "Finds and brings in strong people.",
            signals: ["interviewed a candidate", "referred or recruited someone", "improved how we hire"],
            keywords: "hiring, interview candidate, recruit",
            nudge: "Did you help hire or recruit anyone today?"
        ),
        Competency(
            name: "Develops talent", factor: .people,
            definition: "Helps people grow and reach their potential.",
            signals: ["mentored or coached someone", "gave useful feedback", "gave someone a stretch opportunity"],
            keywords: "mentor, coach, feedback, grow",
            nudge: "Did you help someone learn or grow today?"
        ),
        Competency(
            name: "Values differences", factor: .people,
            definition: "Sees the value in different perspectives, backgrounds, and styles.",
            signals: ["sought out a different viewpoint", "included someone who was left out", "adapted to a different working style"],
            keywords: "perspectives, inclusion, diversity",
            nudge: "Did you seek out a different point of view today?"
        ),
        Competency(
            name: "Builds effective teams", factor: .people,
            definition: "Builds teams with a shared identity that work well together.",
            signals: ["helped the team work better together", "clarified roles on the team", "boosted team trust or morale"],
            keywords: "team, roles, morale, trust",
            nudge: "Did you help your team work better together today?"
        ),
        Competency(
            name: "Communicates effectively", factor: .people,
            definition: "Gets the message across clearly, tailored to each audience.",
            signals: ["presented or explained something clearly", "wrote a clear update or document", "adapted my message to my audience"],
            keywords: "presented, explained, wrote, update",
            nudge: "Did you present or explain something important today?"
        ),
        Competency(
            name: "Drives engagement", factor: .people,
            definition: "Creates an environment where people want to do their best work.",
            signals: ["recognized someone's work", "connected people's work to a purpose", "energized the team"],
            keywords: "motivate, recognize, energize",
            nudge: "Did you recognize or motivate someone today?"
        ),
        Competency(
            name: "Organizational savvy", factor: .people,
            definition: "Understands how the organization really works and navigates it well.",
            signals: ["worked through the right channels", "got buy-in from the right people early", "figured out who really influences a decision"],
            keywords: "politics, channels, buy-in, influence map",
            nudge: "Did you navigate the organization to get something done today?"
        ),
        Competency(
            name: "Persuades", factor: .people,
            definition: "Wins support for ideas with compelling arguments, often without formal authority.",
            signals: ["convinced someone to change their mind", "got buy-in for an idea", "influenced people I don't manage"],
            keywords: "convince, buy-in, influence, pitch",
            nudge: "Did you have to persuade anyone today?"
        ),
        Competency(
            name: "Drives vision and purpose", factor: .people,
            definition: "Paints a compelling picture of the future that motivates others.",
            signals: ["explained the why behind the work", "rallied people around a goal", "shared a vision for where we're headed"],
            keywords: "vision, purpose, rally, why",
            nudge: "Did you explain the bigger why to anyone today?"
        ),

        // MARK: Self
        Competency(
            name: "Courage", factor: .personal,
            definition: "Steps up to hard issues and says what needs to be said.",
            signals: ["raised a hard issue", "pushed back on something I disagreed with", "gave tough feedback"],
            keywords: "spoke up, pushed back, hard conversation",
            nudge: "Did you speak up about something hard today?"
        ),
        Competency(
            name: "Instills trust", factor: .personal,
            definition: "Earns trust through honesty, integrity, and follow-through.",
            signals: ["kept a promise", "was open about bad news", "did the right thing when it was harder"],
            keywords: "honest, integrity, reliable, transparent",
            nudge: "Did you follow through on a promise or share hard news honestly today?"
        ),
        Competency(
            name: "Demonstrates self-awareness", factor: .personal,
            definition: "Uses reflection and feedback to understand their own strengths and weaknesses.",
            signals: ["reflected on what I could do better", "asked for feedback", "noticed how I affected others"],
            keywords: "reflected, asked feedback, my weakness",
            nudge: "What would you do differently about today?"
        ),
        Competency(
            name: "Self-development", factor: .personal,
            definition: "Actively looks for ways to learn and grow.",
            signals: ["studied or took a course", "practiced a new skill", "set a personal growth goal"],
            keywords: "learning, course, practice, study",
            nudge: "Did you learn or practice something new for yourself today?"
        ),
        Competency(
            name: "Manages ambiguity", factor: .personal,
            definition: "Works effectively when things are unclear or keep changing.",
            signals: ["moved forward without full information", "stayed calm when plans changed", "made progress on a poorly defined problem"],
            keywords: "unclear, uncertain, changing, undefined",
            nudge: "Did you have to move forward without all the answers today?"
        ),
        Competency(
            name: "Nimble learning", factor: .personal,
            definition: "Learns quickly in new situations, including from mistakes.",
            signals: ["got up to speed on something new fast", "learned from a mistake or experiment", "figured something out by trial and error"],
            keywords: "learned fast, figured out, new area",
            nudge: "Did you have to learn something new quickly today?"
        ),
        Competency(
            name: "Being resilient", factor: .personal,
            definition: "Bounces back from setbacks and keeps going under pressure.",
            signals: ["recovered from a setback", "kept going after a failure", "stayed steady under pressure"],
            keywords: "setback, pressure, bounced back, persevered",
            nudge: "Did you bounce back from something today?"
        ),
        Competency(
            name: "Situational adaptability", factor: .personal,
            definition: "Adjusts approach in the moment to fit changing situations and people.",
            signals: ["changed my approach when something wasn't working", "adjusted plans on the fly", "switched styles for different people"],
            keywords: "adapted, adjusted, pivoted, flexible",
            nudge: "Did you have to change your approach on the fly today?"
        ),
    ]

    static func competencies(in factor: CompetencyFactor) -> [Competency] {
        all.filter { $0.factor == factor }
    }

    /// Finds a competency by name, forgiving case and small wording differences from the AI.
    static func find(_ name: String) -> Competency? {
        let key = name.normalizedKey
        guard !key.isEmpty else { return nil }
        if let exact = all.first(where: { $0.name.normalizedKey == key }) { return exact }
        return all.first { $0.name.normalizedKey.contains(key) || key.contains($0.name.normalizedKey) }
    }

    /// Ranks competencies for a search like "handling conflict", matching by meaning,
    /// not just words. Returns the best matches first.
    static func search(_ query: String, limit: Int = 8) -> [Competency] {
        let query = query.trimmed
        guard !query.isEmpty else { return [] }
        let lowered = query.lowercased()
        let embedding = NLEmbedding.sentenceEmbedding(for: .english)
        let scored = all.map { competency -> (Competency, Double) in
            let text = "\(competency.name). \(competency.definition) \(competency.signals.joined(separator: ". ")). \(competency.keywords)"
            var score = 0.0
            if let embedding {
                let distance = embedding.distance(between: query, and: text, distanceType: .cosine)
                score += max(0, 1 - distance / 2)
            }
            if competency.name.lowercased().contains(lowered) { score += 1 }
            let words = lowered.split(separator: " ").map(String.init).filter { $0.count > 3 }
            let haystack = text.lowercased()
            if !words.isEmpty {
                score += 0.4 * Double(words.filter { haystack.contains(String($0.prefix(5))) }.count) / Double(words.count)
            }
            return (competency, score)
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    /// The list for Apple's small on-device model: names and a few words each.
    static var compactList: String {
        all.map { "- \($0.name): \($0.keywords)" }.joined(separator: "\n")
    }

    /// The full list for Claude: definitions and signals.
    static var fullList: String {
        all.map { "- \($0.name) (\($0.factor.label)): \($0.definition) Signals: \($0.signals.joined(separator: "; "))." }
            .joined(separator: "\n")
    }
}

/// One tagged day for a competency.
struct CompetencyEvidence: Identifiable {
    let entry: DayEntry
    let tag: CompetencyTag

    var id: String { "\(entry.id.uuidString)-\(tag.competency)" }
}

/// What your recaps show for one competency.
struct CompetencyRecord {
    let competency: Competency
    /// Strongest first, then newest.
    let evidence: [CompetencyEvidence]

    var days: Int { Set(evidence.map(\.entry.date)).count }
    var best: CompetencyStrength? { evidence.first?.tag.level }
    var lastShown: Date? { evidence.map(\.entry.date).max() }

    enum Coverage { case strong, thin, none }

    /// Strong: at least one strong example. Thin: only solid or light ones. None: nothing yet.
    var coverage: Coverage {
        switch best {
        case .strong: .strong
        case .solid, .light: .thin
        case nil: .none
        }
    }

    /// Builds a record for every competency from your recaps.
    @MainActor
    static func build(from entries: [DayEntry]) -> [String: CompetencyRecord] {
        var grouped: [String: [CompetencyEvidence]] = [:]
        for entry in entries {
            for tag in entry.competencyTags {
                guard let competency = CompetencyLibrary.find(tag.competency) else { continue }
                grouped[competency.name, default: []].append(CompetencyEvidence(entry: entry, tag: tag))
            }
        }
        var result: [String: CompetencyRecord] = [:]
        for competency in CompetencyLibrary.all {
            let evidence = (grouped[competency.name] ?? []).sorted {
                $0.tag.level == $1.tag.level ? $0.entry.date > $1.entry.date : $0.tag.level > $1.tag.level
            }
            result[competency.name] = CompetencyRecord(competency: competency, evidence: evidence)
        }
        return result
    }
}

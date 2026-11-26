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

    /// What employers look for in this competency. Edit the text in `CompetencyLibrary.guides`.
    var guide: CompetencyGuide { CompetencyLibrary.guides[name] ?? .empty }
}

/// What employers and interviewers look for in a competency: shown by the "i" button, and
/// given to the AI when it builds competency stories.
struct CompetencyGuide: Sendable {
    /// What doing it well looks like.
    let skilled: [String]
    /// Common ways people fall short.
    let lessSkilled: [String]
    /// What happens when the strength goes too far.
    let overused: [String]
    /// What a strong interview answer shows.
    let whatInterviewersListenFor: [String]
    /// Typical behavioral interview questions.
    let sampleQuestions: [String]

    static let empty = CompetencyGuide(skilled: [], lessSkilled: [], overused: [], whatInterviewersListenFor: [], sampleQuestions: [])
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

    /// Instant word-only matching, shown while the meaning-based search (which runs in the
    /// background in `CompetencySearchIndex`) catches up.
    static func quickSearch(_ query: String, limit: Int = 8) -> [Competency] {
        let query = query.trimmed.lowercased()
        guard !query.isEmpty else { return [] }
        let scored = all.map { ($0, keywordScore(for: $0, query: query)) }.filter { $0.1 > 0 }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    static func searchText(for competency: Competency) -> String {
        "\(competency.name). \(competency.definition) \(competency.signals.joined(separator: ". ")). \(competency.keywords)"
    }

    /// Word matches: a strong boost for the name, a smaller one for definition and signals.
    static func keywordScore(for competency: Competency, query lowered: String) -> Double {
        var score = 0.0
        if competency.name.lowercased().contains(lowered) { score += 1 }
        let words = lowered.split(separator: " ").map(String.init).filter { $0.count > 3 }
        let haystack = searchText(for: competency).lowercased()
        if !words.isEmpty {
            score += 0.4 * Double(words.filter { haystack.contains(String($0.prefix(5))) }.count) / Double(words.count)
        }
        return score
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

// MARK: - What employers look for
//
// Shown by the "i" button on competencies. Written in plain words for this app from
// general knowledge of these competencies, not copied from "FYI: For Your Improvement".
// Edit freely to match your edition of the book.

extension CompetencyLibrary {
    static let guides: [String: CompetencyGuide] = [
        // MARK: Thought
        "Business insight": CompetencyGuide(
            skilled: ["Knows how the company makes and spends money", "Follows the market, customers, and competitors", "Connects day-to-day work to business results", "Spots trends early and explains why they matter"],
            lessSkilled: ["Focuses only on their own function", "Can't explain how their work affects the business", "Misses changes in the market or industry"],
            overused: ["Talks business strategy when the team needs execution", "Chases every trend and loses focus", "Comes across as dismissive of people closer to the details"],
            whatInterviewersListenFor: ["A clear link between your actions and a business outcome", "Real knowledge of the market or customer", "Numbers or impact, not just activity"],
            sampleQuestions: ["Tell me about a decision you made using your understanding of the business.", "How did a change in your industry affect your work, and what did you do?"]
        ),
        "Customer focus": CompetencyGuide(
            skilled: ["Seeks out what customers actually need", "Uses feedback to shape decisions", "Follows through until the customer's problem is solved", "Builds lasting relationships and trust"],
            lessSkilled: ["Assumes they know what customers want", "Treats complaints as a nuisance", "Lets internal convenience win over the customer"],
            overused: ["Says yes to every request, even bad ideas", "Over-customizes at the expense of the bigger picture", "Neglects the team or the business to please one customer"],
            whatInterviewersListenFor: ["How you learned what the customer needed", "What you changed because of it", "The result for the customer, ideally measured"],
            sampleQuestions: ["Tell me about a time you went above and beyond for a customer.", "Describe a time customer feedback changed your plan."]
        ),
        "Financial acumen": CompetencyGuide(
            skilled: ["Reads budgets, costs, and financial results comfortably", "Weighs cost and return before deciding", "Finds savings or revenue", "Explains the financial impact of choices"],
            lessSkilled: ["Avoids the numbers", "Makes decisions without considering cost", "Can't explain the financial impact of their work"],
            overused: ["Cuts costs so hard that quality or morale suffers", "Lets the spreadsheet override judgment", "Gets lost in financial detail"],
            whatInterviewersListenFor: ["Specific numbers you worked with", "How money shaped your decision", "The financial result"],
            sampleQuestions: ["Tell me about a time you managed a budget or reduced costs.", "Describe a decision where you weighed cost against benefit."]
        ),
        "Tech savvy": CompetencyGuide(
            skilled: ["Picks up new tools quickly", "Uses technology to save time or improve results", "Helps others adopt new tools", "Knows which tech fits which problem"],
            lessSkilled: ["Sticks to old ways when better tools exist", "Waits for others to figure out new technology", "Uses tools without understanding them"],
            overused: ["Adds tools for their own sake", "Over-engineers simple problems", "Leaves less technical people behind"],
            whatInterviewersListenFor: ["The specific tool or technology", "Why you chose it", "What it improved and by how much"],
            sampleQuestions: ["Tell me about a time you used technology to improve how work got done.", "How do you get up to speed on a new tool?"]
        ),
        "Manages complexity": CompetencyGuide(
            skilled: ["Breaks messy problems into manageable parts", "Pulls together information from many sources", "Finds the root cause, not just symptoms", "Makes the complicated understandable for others"],
            lessSkilled: ["Jumps to solutions too early", "Gets overwhelmed by too much information", "Fixes symptoms and the problem comes back"],
            overused: ["Over-analyzes and delays action", "Makes simple things complicated", "Loses people in detail"],
            whatInterviewersListenFor: ["How you structured the problem", "The information you gathered and how you weighed it", "The root cause you found and the result"],
            sampleQuestions: ["Tell me about the most complex problem you've solved.", "Describe a time you had to make sense of conflicting information."]
        ),
        "Decision quality": CompetencyGuide(
            skilled: ["Makes timely decisions, even without perfect information", "Weighs options and tradeoffs clearly", "Explains the reasoning behind decisions", "Learns from decisions that didn't work"],
            lessSkilled: ["Puts off decisions", "Decides on gut feel without considering options", "Changes course too often"],
            overused: ["Decides too fast without input", "Won't revisit a decision when facts change", "Takes decisions away from others"],
            whatInterviewersListenFor: ["The options you considered", "How you decided and how quickly", "What happened, including what you learned"],
            sampleQuestions: ["Tell me about a tough decision you made with incomplete information.", "Describe a decision you'd make differently now."]
        ),
        "Balances stakeholders": CompetencyGuide(
            skilled: ["Understands what different groups need", "Finds solutions that work for several sides", "Keeps stakeholders informed", "Handles competing priorities fairly"],
            lessSkilled: ["Favors the loudest voice", "Forgets to involve key groups", "Surprises people with decisions"],
            overused: ["Tries to please everyone and decides nothing", "Spends too long on alignment", "Waters down outcomes to avoid upsetting anyone"],
            whatInterviewersListenFor: ["Who the stakeholders were and what each wanted", "How you weighed and communicated tradeoffs", "The outcome for each side"],
            sampleQuestions: ["Tell me about a time you had to balance competing requests.", "Describe how you got different groups to agree on a direction."]
        ),
        "Global perspective": CompetencyGuide(
            skilled: ["Thinks beyond their own location and culture", "Works well across regions and time zones", "Adapts products or approaches for different markets", "Considers global effects of decisions"],
            lessSkilled: ["Assumes what works locally works everywhere", "Ignores cultural differences", "Leaves remote or international colleagues out"],
            overused: ["Over-complicates local decisions", "Spreads effort too thin across markets", "Loses sight of local needs"],
            whatInterviewersListenFor: ["The cross-border or cross-cultural situation", "How you adapted", "The result in each region"],
            sampleQuestions: ["Tell me about working with people from other countries or cultures.", "Describe a time you adapted something for a different market."]
        ),
        "Cultivates innovation": CompetencyGuide(
            skilled: ["Generates new ideas and better ways of working", "Tests ideas with experiments or prototypes", "Encourages others to try new things", "Turns ideas into real results"],
            lessSkilled: ["Sticks with how it's always been done", "Has ideas but never tests them", "Shuts down unusual suggestions"],
            overused: ["Chases novelty over what works", "Starts too many experiments and finishes few", "Changes things that didn't need changing"],
            whatInterviewersListenFor: ["The idea and where it came from", "How you tested it and handled pushback", "The measurable impact"],
            sampleQuestions: ["Tell me about a new idea you introduced and how it went.", "Describe a time you challenged the usual way of doing something."]
        ),
        "Strategic mindset": CompetencyGuide(
            skilled: ["Looks ahead to future opportunities and risks", "Turns long-term goals into concrete plans", "Connects today's work to where things are headed", "Adjusts strategy as conditions change"],
            lessSkilled: ["Focuses only on the short term", "Has a vision but no plan", "Is surprised by predictable changes"],
            overused: ["Lives in the future and neglects today", "Plans endlessly without acting", "Comes across as impractical"],
            whatInterviewersListenFor: ["The future you anticipated", "The plan you made and how you got buy-in", "What it led to"],
            sampleQuestions: ["Tell me about a time you planned for the long term.", "Describe how you turned a big-picture goal into a plan."]
        ),

        // MARK: Results
        "Action oriented": CompetencyGuide(
            skilled: ["Jumps on problems and opportunities quickly", "Takes initiative without being asked", "Brings energy to tough challenges", "Moves forward despite uncertainty"],
            lessSkilled: ["Waits to be told what to do", "Hesitates until it's too late", "Avoids hard or unfamiliar work"],
            overused: ["Acts before thinking things through", "Burns out themselves or the team", "Leaves a trail of half-finished work"],
            whatInterviewersListenFor: ["What you noticed and how fast you moved", "That you acted without being asked", "The result of acting quickly"],
            sampleQuestions: ["Tell me about a time you took initiative.", "Describe a situation where you had to act quickly."]
        ),
        "Resourcefulness": CompetencyGuide(
            skilled: ["Gets results with limited time, money, or people", "Finds creative workarounds", "Reuses what already exists", "Knows where to find help or resources"],
            lessSkilled: ["Gives up when resources are short", "Waits for more budget or headcount", "Reinvents things that already exist"],
            overused: ["Cuts corners that shouldn't be cut", "Never asks for resources that are truly needed", "Builds fragile workarounds"],
            whatInterviewersListenFor: ["The constraint you faced", "The creative way you got around it", "What you achieved with what you had"],
            sampleQuestions: ["Tell me about a time you did a lot with very little.", "Describe a creative workaround you came up with."]
        ),
        "Directs work": CompetencyGuide(
            skilled: ["Gives clear direction and expectations", "Delegates the right work to the right people", "Removes obstacles for the team", "Checks progress without micromanaging"],
            lessSkilled: ["Leaves people unsure what's expected", "Does everything themselves", "Lets blockers sit"],
            overused: ["Micromanages", "Directs when they should be listening", "Leaves no room for others' ideas"],
            whatInterviewersListenFor: ["How you set expectations and delegated", "How you supported and unblocked people", "What the team delivered"],
            sampleQuestions: ["Tell me about a time you delegated an important task.", "How do you make sure people know what's expected of them?"]
        ),
        "Plans and aligns": CompetencyGuide(
            skilled: ["Breaks goals into clear plans and timelines", "Prioritizes what matters most", "Coordinates with other teams and dependencies", "Adjusts the plan when things change"],
            lessSkilled: ["Works without a plan", "Treats everything as equally urgent", "Is blindsided by dependencies"],
            overused: ["Plans so much that action stalls", "Sticks rigidly to a plan after it stops making sense", "Spends more time in meetings than doing"],
            whatInterviewersListenFor: ["How you planned and prioritized", "How you coordinated with others", "Whether it landed on time and why"],
            sampleQuestions: ["Tell me about a project you planned from start to finish.", "How do you prioritize when everything is urgent?"]
        ),
        "Optimizes work processes": CompetencyGuide(
            skilled: ["Spots inefficiencies and bottlenecks", "Simplifies and improves processes", "Measures before and after", "Keeps improving over time"],
            lessSkilled: ["Tolerates broken processes", "Adds steps instead of removing them", "Improves things without measuring results"],
            overused: ["Tinkers with processes that work fine", "Values process over people or results", "Makes constant changes that confuse people"],
            whatInterviewersListenFor: ["The specific process and its problem", "What you changed", "The measured improvement"],
            sampleQuestions: ["Tell me about a process you improved.", "Describe a time you removed a bottleneck."]
        ),
        "Ensures accountability": CompetencyGuide(
            skilled: ["Follows through on commitments", "Owns mistakes openly", "Tracks progress against goals", "Holds others to their commitments fairly"],
            lessSkilled: ["Lets deadlines slip without saying anything", "Blames others", "Avoids following up with people"],
            overused: ["Becomes rigid or punishing", "Focuses on blame over learning", "Tracks so closely it feels like distrust"],
            whatInterviewersListenFor: ["A commitment you owned", "How you handled it when things went wrong", "What you changed afterward"],
            sampleQuestions: ["Tell me about a time you made a mistake and owned it.", "How have you held a teammate accountable?"]
        ),
        "Drives results": CompetencyGuide(
            skilled: ["Delivers consistently, even under pressure", "Sets and hits challenging goals", "Pushes through obstacles", "Focuses effort on what moves results"],
            lessSkilled: ["Gives up when things get hard", "Confuses activity with results", "Misses deadlines regularly"],
            overused: ["Hits targets at any cost to people", "Ignores how results are achieved", "Can't celebrate or slow down"],
            whatInterviewersListenFor: ["The goal and why it was hard", "What you personally did to push through", "The measurable result"],
            sampleQuestions: ["Tell me about a time you delivered results under pressure.", "Describe a goal you achieved despite obstacles."]
        ),

        // MARK: People
        "Collaborates": CompetencyGuide(
            skilled: ["Works well with others toward shared goals", "Shares information and credit", "Seeks input and builds on others' ideas", "Helps others succeed"],
            lessSkilled: ["Works in a silo", "Holds information back", "Competes with teammates instead of partnering"],
            overused: ["Can't make a decision without group agreement", "Spends too long building consensus", "Avoids individual accountability"],
            whatInterviewersListenFor: ["Who you worked with and your specific role", "How you handled differences", "The shared outcome"],
            sampleQuestions: ["Tell me about a successful collaboration with another team.", "Describe a time you helped a colleague succeed."]
        ),
        "Manages conflict": CompetencyGuide(
            skilled: ["Addresses disagreements directly and early", "Listens to understand all sides", "Finds common ground", "Keeps conflict focused on the issue, not people"],
            lessSkilled: ["Avoids conflict until it blows up", "Takes sides too quickly", "Lets conflict get personal"],
            overused: ["Steps into conflicts that aren't theirs", "Pushes for resolution before people are ready", "Smooths over real issues"],
            whatInterviewersListenFor: ["What the disagreement was and why it mattered", "How you handled it step by step", "How it was resolved and the relationship afterward"],
            sampleQuestions: ["Tell me about a time you resolved a disagreement between team members.", "Describe a conflict you had with a coworker and how you handled it."]
        ),
        "Interpersonal savvy": CompetencyGuide(
            skilled: ["Reads people and situations well", "Builds rapport quickly", "Adjusts style for different people", "Handles sensitive conversations with tact"],
            lessSkilled: ["Uses the same approach with everyone", "Misses social cues", "Comes across as blunt or cold"],
            overused: ["Says what people want to hear", "Seems political or insincere", "Avoids hard truths to keep things pleasant"],
            whatInterviewersListenFor: ["How you read the person or situation", "How you adjusted your approach", "The effect on the relationship"],
            sampleQuestions: ["Tell me about a time you had to win over a difficult person.", "Describe a sensitive conversation you handled well."]
        ),
        "Builds networks": CompetencyGuide(
            skilled: ["Builds relationships inside and outside the organization", "Uses connections to get things done", "Keeps in touch over time", "Helps others connect"],
            lessSkilled: ["Only knows their immediate team", "Reaches out only when they need something", "Struggles to find the right person to ask"],
            overused: ["Spends too much time networking and too little delivering", "Relies on connections over merit", "Seems transactional"],
            whatInterviewersListenFor: ["The relationship and how you built it", "How it helped get something done", "The outcome"],
            sampleQuestions: ["Tell me about a time a relationship helped you achieve something.", "How do you build relationships outside your team?"]
        ),
        "Attracts top talent": CompetencyGuide(
            skilled: ["Spots strong talent", "Runs fair, thoughtful hiring", "Sells the role and team honestly", "Refers and recruits good people"],
            lessSkilled: ["Hires quickly to fill a seat", "Hires people just like themselves", "Makes candidates feel unwelcome"],
            overused: ["Hires stars who don't fit the team", "Over-sells the role", "Spends too long searching for the perfect candidate"],
            whatInterviewersListenFor: ["Your role in finding or selecting someone", "How you judged fit and skill", "How the hire worked out"],
            sampleQuestions: ["Tell me about a great hire you helped make.", "How do you evaluate candidates?"]
        ),
        "Develops talent": CompetencyGuide(
            skilled: ["Coaches and mentors people", "Gives specific, useful feedback", "Offers stretch opportunities", "Celebrates others' growth"],
            lessSkilled: ["Doesn't make time for development", "Gives vague or no feedback", "Keeps the best work for themselves"],
            overused: ["Pushes people too hard or too fast", "Focuses on development over delivery", "Coaches people who didn't ask for it"],
            whatInterviewersListenFor: ["Who you developed and where they started", "What you specifically did to help", "How they grew"],
            sampleQuestions: ["Tell me about someone you mentored and how they grew.", "Describe a time you gave someone difficult feedback to help them improve."]
        ),
        "Values differences": CompetencyGuide(
            skilled: ["Seeks out different perspectives", "Includes people who might be left out", "Adapts to different working styles", "Uses diverse views to improve decisions"],
            lessSkilled: ["Listens mostly to people like themselves", "Overlooks quieter voices", "Expects everyone to work the same way"],
            overused: ["Gathers so many views that decisions stall", "Avoids making calls to keep everyone included", "Focuses on process over outcomes"],
            whatInterviewersListenFor: ["The different perspective you sought or included", "How it changed the outcome", "What you learned"],
            sampleQuestions: ["Tell me about a time a different perspective improved your work.", "How have you included someone who was being left out?"]
        ),
        "Builds effective teams": CompetencyGuide(
            skilled: ["Creates a shared sense of purpose", "Clarifies roles and how people work together", "Builds trust within the team", "Addresses team problems early"],
            lessSkilled: ["Treats the team as a group of individuals", "Leaves roles unclear", "Ignores team tension"],
            overused: ["Protects the team from outside input", "Prioritizes harmony over results", "Builds an in-group that excludes others"],
            whatInterviewersListenFor: ["The state of the team before", "What you did to strengthen it", "How the team performed after"],
            sampleQuestions: ["Tell me about a time you turned a struggling team around.", "How have you built trust on a team?"]
        ),
        "Communicates effectively": CompetencyGuide(
            skilled: ["Explains ideas clearly and simply", "Tailors the message to the audience", "Listens as well as speaks", "Writes clear updates and documents"],
            lessSkilled: ["Uses jargon or too much detail", "Gives the same message to every audience", "Doesn't check for understanding"],
            overused: ["Over-communicates and floods people", "Polishes the message more than the substance", "Talks more than listens"],
            whatInterviewersListenFor: ["Who the audience was", "How you shaped the message for them", "Whether they understood and acted"],
            sampleQuestions: ["Tell me about a time you explained something complex to a non-expert.", "Describe a presentation that went well and why."]
        ),
        "Drives engagement": CompetencyGuide(
            skilled: ["Recognizes people's contributions", "Connects work to a meaningful purpose", "Creates an environment where people want to do their best", "Listens to what motivates each person"],
            lessSkilled: ["Takes people's effort for granted", "Doesn't explain why work matters", "Assumes everyone is motivated the same way"],
            overused: ["Cheerleads without substance", "Avoids hard messages to keep morale up", "Over-praises until it means little"],
            whatInterviewersListenFor: ["What motivated or demotivated people", "What you did about it", "The change in energy or results"],
            sampleQuestions: ["Tell me about a time you motivated a team through a hard stretch.", "How do you recognize good work?"]
        ),
        "Organizational savvy": CompetencyGuide(
            skilled: ["Understands how decisions really get made", "Works through the right channels", "Gets buy-in from key people early", "Navigates politics without playing games"],
            lessSkilled: ["Is surprised by politics", "Goes around people and creates resistance", "Doesn't know who influences decisions"],
            overused: ["Seems political or manipulative", "Spends more energy on positioning than work", "Avoids anything risky to their standing"],
            whatInterviewersListenFor: ["How you mapped who mattered", "How you got buy-in", "What you got done because of it"],
            sampleQuestions: ["Tell me about a time you navigated a complex organization to get something done.", "How do you get buy-in from senior leaders?"]
        ),
        "Persuades": CompetencyGuide(
            skilled: ["Builds compelling, evidence-based arguments", "Tailors the case to what others care about", "Influences without formal authority", "Handles objections well"],
            lessSkilled: ["Relies on authority or repetition", "Doesn't consider what others care about", "Gives up after the first no"],
            overused: ["Pushes too hard and damages relationships", "Wins arguments but loses trust", "Won't take no for an answer"],
            whatInterviewersListenFor: ["Who you needed to convince and why it was hard", "How you built and tailored your case", "Whether they changed their mind and the result"],
            sampleQuestions: ["Tell me about a time you persuaded someone who disagreed with you.", "Describe how you influenced people you didn't manage."]
        ),
        "Drives vision and purpose": CompetencyGuide(
            skilled: ["Paints a clear picture of the future", "Explains why the work matters", "Rallies people around a shared goal", "Keeps the vision alive through setbacks"],
            lessSkilled: ["Focuses only on tasks, never the why", "Has a vision but can't communicate it", "Loses people's belief when things get hard"],
            overused: ["Oversells the vision", "Neglects practical details", "Dismisses concerns as negativity"],
            whatInterviewersListenFor: ["The vision and how you communicated it", "How people responded", "What it achieved"],
            sampleQuestions: ["Tell me about a time you rallied people around a goal.", "How have you explained the why behind a big change?"]
        ),

        // MARK: Self
        "Courage": CompetencyGuide(
            skilled: ["Raises hard issues others avoid", "Pushes back respectfully when they disagree", "Gives tough feedback honestly", "Stands by their convictions under pressure"],
            lessSkilled: ["Stays quiet to avoid conflict", "Goes along with decisions they disagree with", "Softens feedback until it loses meaning"],
            overused: ["Picks fights that don't matter", "Comes across as abrasive", "Won't let go after a decision is made"],
            whatInterviewersListenFor: ["What was hard or risky to say", "How you raised it", "What changed as a result"],
            sampleQuestions: ["Tell me about a time you spoke up when others didn't.", "Describe a time you disagreed with your manager."]
        ),
        "Instills trust": CompetencyGuide(
            skilled: ["Keeps promises", "Is honest, even with bad news", "Acts with integrity when it's hard", "Treats information with discretion"],
            lessSkilled: ["Over-promises and under-delivers", "Hides bad news", "Says different things to different people"],
            overused: ["Is so cautious about commitments they rarely make any", "Shares too much in the name of transparency", "Is rigid about rules in gray areas"],
            whatInterviewersListenFor: ["A situation where trust was at stake", "What you chose to do and why", "How it affected the relationship"],
            sampleQuestions: ["Tell me about a time you had to deliver bad news.", "Describe a time you did the right thing when it was difficult."]
        ),
        "Demonstrates self-awareness": CompetencyGuide(
            skilled: ["Knows their strengths and weaknesses", "Asks for feedback and acts on it", "Reflects on mistakes", "Notices how they affect others"],
            lessSkilled: ["Is surprised by feedback", "Gets defensive about criticism", "Repeats the same mistakes"],
            overused: ["Is overly self-critical", "Dwells on weaknesses instead of acting", "Seeks feedback so often it slows decisions"],
            whatInterviewersListenFor: ["A specific insight about yourself", "Where it came from, such as feedback or reflection", "What you changed"],
            sampleQuestions: ["What's a piece of feedback that changed how you work?", "Tell me about a weakness and how you've worked on it."]
        ),
        "Self-development": CompetencyGuide(
            skilled: ["Actively seeks to learn and grow", "Sets personal development goals", "Takes on stretch assignments", "Applies what they learn"],
            lessSkilled: ["Waits for the company to develop them", "Avoids unfamiliar work", "Learns things but never applies them"],
            overused: ["Chases growth at the expense of current work", "Collects courses without using them", "Changes direction too often"],
            whatInterviewersListenFor: ["What you set out to learn and why", "How you learned it", "How you've used it"],
            sampleQuestions: ["Tell me about a skill you taught yourself.", "How do you keep developing in your role?"]
        ),
        "Manages ambiguity": CompetencyGuide(
            skilled: ["Makes progress without full information", "Stays calm when plans change", "Brings clarity for others", "Comfortable with open-ended problems"],
            lessSkilled: ["Freezes without clear direction", "Gets anxious when plans change", "Needs every detail before starting"],
            overused: ["Leaves things vague when clarity is needed", "Moves ahead on too many assumptions", "Frustrates people who need structure"],
            whatInterviewersListenFor: ["What was unclear", "How you moved forward anyway", "The outcome and what you learned"],
            sampleQuestions: ["Tell me about a time you had to work without clear direction.", "Describe a project where the goals kept changing."]
        ),
        "Nimble learning": CompetencyGuide(
            skilled: ["Gets up to speed quickly in new areas", "Learns from mistakes and experiments", "Asks good questions", "Applies lessons to new situations"],
            lessSkilled: ["Sticks to what they know", "Makes the same mistakes twice", "Takes a long time to adapt to new situations"],
            overused: ["Jumps between topics without depth", "Experiments where reliability matters", "Gets bored once things become routine"],
            whatInterviewersListenFor: ["How new the situation was", "How you learned quickly", "How well you performed"],
            sampleQuestions: ["Tell me about a time you had to learn something new quickly.", "Describe a mistake you learned from."]
        ),
        "Being resilient": CompetencyGuide(
            skilled: ["Bounces back from setbacks", "Stays steady under pressure", "Learns from failure and keeps going", "Helps others stay positive"],
            lessSkilled: ["Gets discouraged and gives up", "Takes setbacks personally", "Lets stress affect their work or others"],
            overused: ["Pushes through when they should step back", "Hides struggles instead of asking for help", "Expects others to handle the same pressure"],
            whatInterviewersListenFor: ["The setback and how it affected you", "What you did to recover", "What happened next"],
            sampleQuestions: ["Tell me about a time you failed and how you recovered.", "How do you handle sustained pressure?"]
        ),
        "Situational adaptability": CompetencyGuide(
            skilled: ["Changes approach when something isn't working", "Adjusts style for different people and situations", "Stays effective when things shift", "Reads what a situation needs"],
            lessSkilled: ["Uses the same approach no matter what", "Resists changing course", "Struggles when circumstances shift"],
            overused: ["Seems inconsistent or hard to predict", "Changes direction too easily", "Lacks a clear point of view"],
            whatInterviewersListenFor: ["What changed in the situation", "How you adjusted", "Why the new approach worked better"],
            sampleQuestions: ["Tell me about a time you had to change your approach mid-project.", "Describe how you adjust your style for different people."]
        ),
    ]
}

/// Meaning-based competency search ("handling conflict" finds Manages conflict), kept off
/// the main thread so typing stays instant.
///
/// Apple's language model is loaded once, and each competency's meaning is worked out once;
/// after that each search only has to look at what you typed.
actor CompetencySearchIndex {
    static let shared = CompetencySearchIndex()

    private var embedding: NLEmbedding?
    private var vectors: [String: [Double]] = [:]
    private var isLoaded = false

    /// Loads the model ahead of time, so the first search is fast too.
    func warmUp() {
        load()
    }

    /// The best-matching competency names, best first.
    func search(_ query: String, limit: Int = 8) -> [String] {
        let query = query.trimmed
        guard !query.isEmpty else { return [] }
        load()
        let lowered = query.lowercased()
        let queryVector = embedding?.vector(for: query)

        let scored = CompetencyLibrary.all.map { competency -> (String, Double) in
            var score = CompetencyLibrary.keywordScore(for: competency, query: lowered)
            if let queryVector, let vector = vectors[competency.name] {
                // Cosine similarity runs from -1 to 1; scale it to 0...1.
                score += (1 + Self.cosine(queryVector, vector)) / 2
            }
            return (competency.name, score)
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    /// How close in meaning `query` is to each text, from 0 to 1, or nil if the language
    /// model isn't available. Used to rank journal entries for interview prep.
    func similarities(of query: String, to texts: [String]) -> [Double]? {
        load()
        guard let embedding, let queryVector = embedding.vector(for: query) else { return nil }
        return texts.map { text in
            guard let vector = embedding.vector(for: text) else { return 0 }
            return (1 + Self.cosine(queryVector, vector)) / 2
        }
    }

    private func load() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return }
        self.embedding = embedding
        for competency in CompetencyLibrary.all {
            if let vector = embedding.vector(for: CompetencyLibrary.searchText(for: competency)) {
                vectors[competency.name] = vector
            }
        }
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for index in a.indices {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}

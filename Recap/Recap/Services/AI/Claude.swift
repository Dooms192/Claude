import Foundation

/// Calls Claude through the Anthropic Messages API.
///
/// This is separate from a Claude Pro subscription: the API is pay-as-you-go,
/// using a key from console.anthropic.com. The key is stored in the Keychain.
struct ClaudeClient: Sendable {
    let apiKey: String

    static let model = "claude-opus-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Sends a prompt and decodes Claude's answer as JSON that matches `schema`.
    func structured<T: Decodable>(
        _ type: T.Type,
        system: String,
        prompt: String,
        schema: [String: Any],
        maxTokens: Int = 16000
    ) async throws -> T {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": prompt]],
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": schema],
            ],
            // If Claude's safety checks decline a request, Anthropic retries it on a
            // fallback model automatically instead of returning nothing.
            "fallbacks": "default",
        ]
        let response = try await send(body)
        guard let text = response.content.last(where: { $0.type == "text" })?.text,
              let json = text.data(using: .utf8)
        else { throw ClaudeError.emptyResponse }
        do {
            return try JSONDecoder().decode(T.self, from: json)
        } catch {
            throw ClaudeError.unreadableResponse
        }
    }

    /// A tiny request to check that the key works.
    func verifyKey() async throws {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 64,
            "output_config": ["effort": "low"],
            "messages": [["role": "user", "content": "Reply with the word OK."]],
        ]
        _ = try await send(body)
    }

    private func send(_ body: [String: Any]) async throws -> MessageResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeError.network(error.localizedDescription)
        }
        guard let http = urlResponse as? HTTPURLResponse else { throw ClaudeError.network("No response.") }
        guard http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error.message
            throw ClaudeError.http(http.statusCode, message)
        }
        let decoded = try JSONDecoder().decode(MessageResponse.self, from: data)
        switch decoded.stopReason {
        case "refusal": throw ClaudeError.refused
        case "max_tokens": throw ClaudeError.truncated
        default: return decoded
        }
    }

    private struct MessageResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    private struct APIErrorEnvelope: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }
}

enum ClaudeError: LocalizedError {
    case network(String)
    case http(Int, String?)
    case refused
    case truncated
    case emptyResponse
    case unreadableResponse

    var errorDescription: String? {
        switch self {
        case .network(let message):
            return "Couldn't reach Claude. Check your internet connection. (\(message))"
        case .http(401, _):
            return "Your Claude API key was rejected. Check it in Settings."
        case .http(402, _), .http(403, _):
            return "Your Anthropic account can't make this request. Check your billing at console.anthropic.com."
        case .http(429, _):
            return "Claude is busy or you've hit your rate limit. Try again in a minute."
        case .http(let code, let message):
            return "Claude returned an error (\(code)). \(message ?? "")"
        case .refused:
            return "Claude declined this request."
        case .truncated:
            return "Claude's answer was cut off. Try a shorter request."
        case .emptyResponse, .unreadableResponse:
            return "Claude's answer couldn't be read. Try again."
        }
    }
}

// MARK: - Claude engines

struct ClaudeSummarizer: RecapSummarizer {
    let client: ClaudeClient
    let displayName = "Claude"

    init(apiKey: String) { client = ClaudeClient(apiKey: apiKey) }

    func summarize(transcript: String, day: Date, goalTitles: [String], projectNames: [String]) async throws -> DailySummary {
        try await client.structured(
            DailySummary.self,
            system: Prompts.dailyInstructions,
            prompt: Prompts.dailyPrompt(transcript: transcript, day: day, goalTitles: goalTitles, projectNames: projectNames),
            schema: JSONSchema.object([
                "headline": JSONSchema.string("A short headline for the day, under 10 words"),
                "summary": JSONSchema.string("Two to four sentences summarizing the day, first person"),
                "accomplishments": JSONSchema.strings("Concrete things I got done, each short and specific"),
                "challenges": JSONSchema.strings("Problems or hard moments, and how I handled them"),
                "skills": JSONSchema.strings("Skills I showed, such as leadership or debugging"),
                "goalUpdates": JSONSchema.array(
                    JSONSchema.object([
                        "goalTitle": JSONSchema.string("The exact goal title from my list"),
                        "note": JSONSchema.string("One sentence on what I did toward this goal"),
                        "targetDate": JSONSchema.string("A deadline I mentioned, as YYYY-MM-DD, or an empty string"),
                    ]),
                    "Progress on my listed goals. Only goals I actually worked on today."
                ),
                "suggestedGoals": JSONSchema.array(
                    JSONSchema.object([
                        "goalTitle": JSONSchema.string("A short title for the goal, under 8 words"),
                        "note": JSONSchema.string("One sentence on what I did toward it today"),
                        "targetDate": JSONSchema.string("A deadline I mentioned, as YYYY-MM-DD, or an empty string"),
                    ]),
                    "Longer-term goals I said I'm working toward that are NOT in my list. Empty if none."
                ),
                "projects": JSONSchema.array(
                    JSONSchema.object([
                        "projectName": JSONSchema.string("An exact name from my project list if the work belongs to it, otherwise a short new name of 2 to 5 words"),
                        "note": JSONSchema.string("What I did on it today, in 1 to 2 sentences"),
                        "status": JSONSchema.oneOf(["started", "progressed", "blocked", "completed"], "How the project moved today"),
                        "blockers": JSONSchema.strings("Blockers I mentioned. Empty if none."),
                        "nextSteps": JSONSchema.strings("Next steps I mentioned. Empty if none."),
                    ]),
                    "Ongoing multi-day projects I worked on today. No one-off tasks. Empty if none."
                ),
            ])
        )
    }
}

struct ClaudeCoach: InterviewCoachEngine {
    let client: ClaudeClient
    let displayName = "Claude"

    /// How many of the most relevant entries Claude reads per request.
    static let maxEntries = 25

    init(apiKey: String) { client = ClaudeClient(apiKey: apiKey) }

    func prepare(request: String, context: InterviewContext) async throws -> InterviewPrep {
        try await client.structured(
            InterviewPrep.self,
            system: Prompts.interviewInstructions,
            prompt: Prompts.interviewPrompt(
                request: request,
                context: context,
                entryLimit: Self.maxEntries,
                transcriptLimit: 1500,
                projectLimit: 5,
                projectDayLimit: 40
            ),
            schema: JSONSchema.object([
                "overview": JSONSchema.string("Two or three sentences on what this interviewer likely wants and which experiences fit best"),
                "stories": JSONSchema.array(
                    JSONSchema.object([
                        "title": JSONSchema.string("A short title for the story"),
                        "whyItFits": JSONSchema.string("One sentence on why this story fits the interview"),
                        "situation": JSONSchema.string("Situation: the context and background"),
                        "task": JSONSchema.string("Task: what I was responsible for"),
                        "action": JSONSchema.string("Action: the specific steps I took"),
                        "result": JSONSchema.string("Result: the outcome, or what to find out if it isn't recorded"),
                        "howToSayIt": JSONSchema.string("A natural first-person answer to say out loud in 60 to 90 seconds"),
                        "dates": JSONSchema.strings("Entry dates this story draws on, as YYYY-MM-DD"),
                    ]),
                    "Three to five STAR stories, strongest first"
                ),
                "tips": JSONSchema.strings("Three to six short, practical tips for this interview"),
            ])
        )
    }
}

/// Writes a project's overview and highlights with Claude.
struct ClaudeProjectWriter {
    let client: ClaudeClient
    static let dayLimit = 80

    init(apiKey: String) { client = ClaudeClient(apiKey: apiKey) }

    func write(_ project: ProjectSnapshot) async throws -> ProjectInsight {
        try await client.structured(
            ProjectInsight.self,
            system: Prompts.projectInstructions,
            prompt: Prompts.projectPrompt(project, dayLimit: Self.dayLimit),
            schema: JSONSchema.object([
                "summary": JSONSchema.string("2 to 4 sentences on what the project is and where it stands now"),
                "done": JSONSchema.strings("What's been finished"),
                "problems": JSONSchema.strings("Current open problems or blockers"),
                "nextSteps": JSONSchema.strings("What's next"),
                "wins": JSONSchema.strings("Key wins worth remembering for a review or interview"),
                "skills": JSONSchema.strings("Skills I used on it"),
                "blockersSolved": JSONSchema.array(
                    JSONSchema.object([
                        "blocker": JSONSchema.string("The blocker"),
                        "resolution": JSONSchema.string("How I solved it"),
                    ]),
                    "Blockers that were later solved, each with how"
                ),
            ])
        )
    }
}

/// Small helpers for writing the JSON schemas Claude's answers must follow.
enum JSONSchema {
    static func boolean(_ description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
    }

    static func oneOf(_ values: [String], _ description: String) -> [String: Any] {
        ["type": "string", "enum": values, "description": description]
    }

    static func string(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    static func strings(_ description: String) -> [String: Any] {
        ["type": "array", "description": description, "items": ["type": "string"]]
    }

    static func array(_ items: [String: Any], _ description: String) -> [String: Any] {
        ["type": "array", "description": description, "items": items]
    }

    static func object(_ properties: [String: [String: Any]]) -> [String: Any] {
        [
            "type": "object",
            "properties": properties,
            "required": properties.keys.sorted(),
            "additionalProperties": false,
        ]
    }
}

import Foundation
import SwiftData

/// A saved interview-prep run: what you asked for and the STAR stories you got back.
@Model
final class PrepSession {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var query: String = ""
    var engine: String = ""
    var note: String?
    var entriesUsed: Int = 0
    var resultData: Data = Data()
    /// Set when the prep used stories from one project only.
    var projectName: String?

    init(query: String, engine: String, note: String?, entriesUsed: Int, prep: InterviewPrep, projectName: String? = nil) {
        self.projectName = projectName
        self.query = query
        self.engine = engine
        self.note = note
        self.entriesUsed = entriesUsed
        self.resultData = (try? JSONEncoder().encode(prep)) ?? Data()
    }

    var prep: InterviewPrep? {
        try? JSONDecoder().decode(InterviewPrep.self, from: resultData)
    }
}

/// The interview coach's answer.
struct InterviewPrep: Codable, Hashable, Sendable {
    var overview: String
    var stories: [STARStory]
    var tips: [String]

    var plainText: String {
        var lines = [overview, ""]
        for (index, story) in stories.enumerated() {
            lines.append("\(index + 1). \(story.title)")
            lines.append("Why it fits: \(story.whyItFits)")
            lines.append("Situation: \(story.situation)")
            lines.append("Task: \(story.task)")
            lines.append("Action: \(story.action)")
            lines.append("Result: \(story.result)")
            lines.append("How to say it: \(story.howToSayIt)")
            if !story.dates.isEmpty { lines.append("From: \(story.dates.joined(separator: ", "))") }
            lines.append("")
        }
        if !tips.isEmpty {
            lines.append("Tips")
            lines.append(contentsOf: tips.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }
}

/// One interview story in STAR format: Situation, Task, Action, Result.
struct STARStory: Codable, Hashable, Sendable {
    var title: String
    var whyItFits: String
    var situation: String
    var task: String
    var action: String
    var result: String
    var howToSayIt: String
    var dates: [String]
}

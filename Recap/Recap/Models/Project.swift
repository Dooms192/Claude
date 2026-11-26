import Foundation
import SwiftData
import SwiftUI

/// Where a project stands overall.
enum ProjectStatus: String, CaseIterable, Codable, Identifiable {
    case active, paused, completed, inactive

    var id: Self { self }

    var label: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .completed: "Completed"
        case .inactive: "Inactive"
        }
    }

    var systemImage: String {
        switch self {
        case .active: "bolt.fill"
        case .paused: "pause.circle.fill"
        case .completed: "checkmark.seal.fill"
        case .inactive: "moon.zzz.fill"
        }
    }

    var tint: Color {
        switch self {
        case .active: .green
        case .paused: .orange
        case .completed: .blue
        case .inactive: .secondary
        }
    }
}

/// What a single day's recap said about a project.
enum ProjectSignal: String, CaseIterable, Codable {
    case started, progressed, blocked, completed

    /// Accepts whatever wording the AI used and falls back to "progressed".
    init(loose text: String) {
        self = ProjectSignal(rawValue: text.normalizedKey) ?? .progressed
    }

    var label: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .started: "flag.fill"
        case .progressed: "arrow.up.right.circle.fill"
        case .blocked: "exclamationmark.octagon.fill"
        case .completed: "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .started: .purple
        case .progressed: .blue
        case .blocked: .red
        case .completed: .green
        }
    }
}

/// One day's note about one project, stored on the `DayEntry`.
struct ProjectNote: Codable, Hashable, Sendable {
    var projectName: String
    var note: String
    /// started, progressed, blocked, or completed.
    var status: String
    var blockers: [String]
    var nextSteps: [String]

    var signal: ProjectSignal { ProjectSignal(loose: status) }
}

/// A body of work that spans many days, detected from your recaps.
@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var details: String = ""
    var statusRaw: String = ProjectStatus.active.rawValue
    /// The first day a recap mentioned it.
    var startDate: Date = Date()
    /// The most recent day a recap mentioned it.
    var lastMentioned: Date = Date()
    var targetDate: Date?
    /// When you last answered "Still working on this?" with yes.
    var stillWorkingConfirmedAt: Date?
    var insightData: Data = Data()
    var insightUpdatedAt: Date?
    var colorName: String = "indigo"
    var icon: String = "folder.fill"
    var createdAt: Date = Date()

    /// Days whose recap mentioned this project.
    var entries: [DayEntry]? = []

    init(name: String, details: String = "", startDate: Date = Date()) {
        self.name = name
        self.details = details
        self.startDate = startDate
        self.lastMentioned = startDate
        self.colorName = ProjectPalette.color(for: name)
    }

    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var insight: ProjectInsight? {
        guard !insightData.isEmpty else { return nil }
        return try? JSONDecoder().decode(ProjectInsight.self, from: insightData)
    }

    func setInsight(_ insight: ProjectInsight) {
        insightData = (try? JSONEncoder().encode(insight)) ?? Data()
        insightUpdatedAt = Date()
    }

    var color: Color { ProjectPalette.color(named: colorName) }

    /// Newest first.
    var timeline: [DayEntry] {
        (entries ?? []).sorted { $0.date > $1.date }
    }

    var daysWorked: Int {
        Set((entries ?? []).map(\.date)).count
    }

    func note(in entry: DayEntry) -> ProjectNote? {
        entry.projectNotes.first { $0.projectName.normalizedKey == name.normalizedKey }
    }

    /// The latest of "last mentioned" and "you said you're still on it".
    var lastActivity: Date {
        max(lastMentioned, stillWorkingConfirmedAt ?? .distantPast)
    }

    /// Goals linked to the days you worked on this project.
    var relatedGoals: [Goal] {
        var seen = Set<UUID>()
        var result: [Goal] = []
        for entry in timeline {
            for goal in entry.goals ?? [] where seen.insert(goal.id).inserted {
                result.append(goal)
            }
        }
        return result
    }

    /// One line for the list: the latest note, or the status.
    var oneLineStatus: String {
        if let latest = timeline.first, let note = note(in: latest), !note.note.isEmpty {
            return note.note
        }
        return status.label
    }
}

/// A project name you said isn't a project, so it isn't suggested again.
@Model
final class IgnoredProjectName {
    var name: String = ""
    var createdAt: Date = Date()

    init(name: String) {
        self.name = name.trimmed
    }
}

/// The AI-written overview and highlights for a project.
struct ProjectInsight: Codable, Hashable, Sendable {
    struct Solved: Codable, Hashable, Sendable {
        var blocker: String
        var resolution: String
    }

    /// What the project is and where it stands.
    var summary: String
    var done: [String]
    var problems: [String]
    var nextSteps: [String]
    var wins: [String]
    var skills: [String]
    var blockersSolved: [Solved]
}

/// Colors and icons you can give a project.
enum ProjectPalette {
    static let colorNames = ["indigo", "blue", "teal", "green", "yellow", "orange", "red", "pink", "purple", "brown"]

    static let icons = [
        "folder.fill", "hammer.fill", "chevron.left.forwardslash.chevron.right", "paintbrush.fill",
        "chart.bar.fill", "megaphone.fill", "book.fill", "graduationcap.fill", "briefcase.fill",
        "lightbulb.fill", "wrench.and.screwdriver.fill", "person.2.fill", "dollarsign.circle.fill",
        "airplane", "house.fill", "heart.fill",
    ]

    static func color(named name: String) -> Color {
        switch name {
        case "blue": .blue
        case "teal": .teal
        case "green": .green
        case "yellow": .yellow
        case "orange": .orange
        case "red": .red
        case "pink": .pink
        case "purple": .purple
        case "brown": .brown
        default: .indigo
        }
    }

    /// A stable starting color based on the name, so new projects don't all look the same.
    static func color(for name: String) -> String {
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colorNames[sum % colorNames.count]
    }
}

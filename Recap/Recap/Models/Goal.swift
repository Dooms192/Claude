import Foundation
import SwiftData

@Model
final class Goal {
    var id: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var createdAt: Date = Date()
    var targetDate: Date?
    var isArchived: Bool = false

    /// Days whose recap made progress on this goal (filled in by the AI summary).
    var entries: [DayEntry]? = []

    init(title: String, details: String = "", targetDate: Date? = nil) {
        self.title = title
        self.details = details
        self.targetDate = targetDate
    }

    var progressEntries: [DayEntry] {
        (entries ?? []).sorted { $0.date > $1.date }
    }
}

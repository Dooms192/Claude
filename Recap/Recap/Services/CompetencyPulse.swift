import Foundation
import SwiftData
import UserNotifications

/// The optional weekly competency notification, for example: "This week you showed Drives
/// results 3 times. You haven't logged Develops talent in a month."
///
/// Like the project pulse, its text is worked out when it's scheduled, so it's rescheduled
/// every time you open the app.
enum CompetencyPulse {
    static let identifier = "weekly-competency-pulse"
    static let enabledKey = "competencyPulseEnabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    @MainActor
    static func reschedule(in context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard isEnabled else { return }

        let entries = (try? context.fetch(FetchDescriptor<DayEntry>())) ?? []
        guard let body = message(for: entries) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Competency pulse"
        content.body = body
        content.sound = .default

        // Sunday at 6:30 PM, a little after the project pulse.
        var components = DateComponents()
        components.weekday = 1
        components.hour = 18
        components.minute = 30
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    @MainActor
    static func message(for entries: [DayEntry], now: Date = Date()) -> String? {
        let calendar = Calendar.current
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
              let monthAgo = calendar.date(byAdding: .day, value: -30, to: now)
        else { return nil }

        var thisWeek: [String: Int] = [:]
        var lastSeen: [String: Date] = [:]
        for entry in entries {
            for tag in entry.competencyTags {
                guard let name = CompetencyLibrary.find(tag.competency)?.name else { continue }
                if entry.date >= calendar.startOfDay(for: weekAgo) { thisWeek[name, default: 0] += 1 }
                lastSeen[name] = max(lastSeen[name] ?? .distantPast, entry.date)
            }
        }
        guard !lastSeen.isEmpty else { return nil }

        var parts: [String] = []
        if let top = thisWeek.max(by: { $0.value < $1.value }) {
            parts.append("This week you showed \(top.key) \(top.value == 1 ? "once" : "\(top.value) times").")
        } else {
            parts.append("No competencies were tagged this week.")
        }
        if let faded = lastSeen.filter({ $0.value < monthAgo }).min(by: { $0.value < $1.value }) {
            parts.append("You haven't logged \(faded.key) in a month.")
        }
        return parts.joined(separator: " ")
    }
}

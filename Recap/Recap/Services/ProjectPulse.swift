import Foundation
import SwiftData
import UserNotifications

/// The optional weekly "Project pulse" notification, for example: "You moved 3 projects
/// forward this week. 'Checkout redesign' hasn't been mentioned in 2 weeks."
///
/// Its text is worked out when it's scheduled, so it's rescheduled every time you open the
/// app, which also happens whenever you record a recap.
enum ProjectPulse {
    static let identifier = "weekly-project-pulse"
    static let enabledKey = "projectPulseEnabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    @MainActor
    static func reschedule(in context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard isEnabled else { return }

        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        guard let body = message(for: projects) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Project pulse"
        content.body = body
        content.sound = .default

        // Sunday at 6 PM.
        var components = DateComponents()
        components.weekday = 1
        components.hour = 18
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    @MainActor
    static func message(for projects: [Project], now: Date = Date()) -> String? {
        let calendar = Calendar.current
        guard !projects.isEmpty,
              let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
              let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now)
        else { return nil }

        let moved = projects.filter { $0.lastMentioned >= calendar.startOfDay(for: weekAgo) }.count
        var parts: [String] = []
        switch moved {
        case 0: parts.append("No projects moved forward this week.")
        case 1: parts.append("You moved 1 project forward this week.")
        default: parts.append("You moved \(moved) projects forward this week.")
        }

        let stale = projects
            .filter { ($0.status == .active || $0.status == .inactive) && $0.lastActivity < twoWeeksAgo }
            .min { $0.lastActivity < $1.lastActivity }
        if let stale {
            let weeks = max(2, (calendar.dateComponents([.day], from: stale.lastActivity, to: now).day ?? 14) / 7)
            parts.append("'\(stale.name)' hasn't been mentioned in \(weeks) weeks.")
        }
        return parts.joined(separator: " ")
    }
}

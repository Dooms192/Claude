import SwiftData
import SwiftUI

/// Lays out chips left to right, wrapping onto new lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width
            widest = max(widest, x)
            x += spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct Chip: View {
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// A titled, rounded section used throughout the detail screens.
struct SectionCard<Content: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .font(.headline)
            } else {
                Text(title).font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(.secondary)
                    Text(item)
                }
            }
        }
    }
}

/// The summary of one day: shown in the journal and right after you record.
struct EntrySummaryContent: View {
    let entry: DayEntry

    @Environment(\.modelContext) private var context
    @Query private var allGoals: [Goal]

    var body: some View {
        let progress = entry.progressUpdates(existing: allGoals)
        let suggestions = entry.goalSuggestions(existing: allGoals)

        VStack(alignment: .leading, spacing: 16) {
            if entry.isSummarized {
                Text(entry.summary)
                    .font(.body)

                if !entry.accomplishments.isEmpty {
                    SectionCard(title: "What I got done", systemImage: "checkmark.circle") {
                        BulletList(items: entry.accomplishments)
                    }
                }
                if !entry.challenges.isEmpty {
                    SectionCard(title: "Challenges", systemImage: "mountain.2") {
                        BulletList(items: entry.challenges)
                    }
                }
                if !progress.isEmpty {
                    SectionCard(title: "Goal progress", systemImage: "target") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(progress.enumerated()), id: \.offset) { _, update in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(update.goalTitle).font(.subheadline.weight(.semibold))
                                    Text(update.note).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !suggestions.isEmpty {
                    SectionCard(title: "Sounds like a goal", systemImage: "plus.circle") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("You mentioned working toward these. Add them to track your progress over time.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                                GoalSuggestionRow(suggestion: suggestion) {
                                    withAnimation {
                                        _ = GoalLinker.createGoal(title: suggestion.goalTitle, in: context)
                                    }
                                } onDismiss: {
                                    withAnimation {
                                        entry.dismissSuggestion(suggestion.goalTitle)
                                        try? context.save()
                                    }
                                }
                            }
                        }
                    }
                }
                if !entry.skills.isEmpty {
                    SectionCard(title: "Skills I used", systemImage: "star") {
                        FlowLayout {
                            ForEach(entry.skills, id: \.self) { Chip(text: $0) }
                        }
                    }
                }
            } else {
                Label("Not summarized yet", systemImage: "sparkles")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GoalSuggestionRow: View {
    let suggestion: GoalUpdate
    var onAdd: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.goalTitle).font(.subheadline.weight(.semibold))
                if !suggestion.note.isEmpty {
                    Text(suggestion.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Add goal", action: onAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not a goal")
        }
    }
}

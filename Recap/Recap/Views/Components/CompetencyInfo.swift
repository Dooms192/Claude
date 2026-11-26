import SwiftData
import SwiftUI

/// Where an "i" button sits, which decides which action buttons its pop-up shows.
enum CompetencyInfoPlacement {
    /// Shows "See my evidence" and "Build a STAR story for this".
    case standard
    /// On the competency's own detail screen: no "See my evidence" link.
    case detailScreen
    /// Inside another sheet, where jumping to another screen would strand that sheet:
    /// shows the information only.
    case insideSheet

    var showsEvidenceLink: Bool { self == .standard }
    var showsBuildStory: Bool { self != .insideSheet }
}

/// The "i" button: what employers look for in a competency.
///
/// Opens as a popover anchored to the button on the unfolded Duo (regular width), and as a
/// half-height sheet you can pull up on folded and regular iPhones (compact width). SwiftUI
/// picks between the two from the size class.
struct CompetencyInfoButton: View {
    let competency: Competency
    var placement: CompetencyInfoPlacement = .standard

    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("What employers look for in \(competency.name)")
        .popover(isPresented: $showing) {
            CompetencyInfoView(competency: competency, placement: placement) {
                showing = false
            }
            // Flexible bounds, not a fixed size: a comfortable reading width in the popover.
            .frame(minWidth: 320, idealWidth: 440, maxWidth: 560, idealHeight: 640)
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

/// What employers and interviewers look for in one competency.
struct CompetencyInfoView: View {
    let competency: Competency
    let placement: CompetencyInfoPlacement
    var onClose: () -> Void

    @Environment(AppRouter.self) private var router
    @Query private var entries: [DayEntry]

    private var guide: CompetencyGuide { competency.guide }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                section("What employers look for", systemImage: "ear", tint: .accentColor, items: guide.whatInterviewersListenFor)
                section("Skilled", systemImage: "checkmark.circle.fill", tint: .green, items: guide.skilled)
                section("Less skilled", systemImage: "exclamationmark.circle.fill", tint: .orange, items: guide.lessSkilled)
                section(
                    "Overused",
                    systemImage: "flame.fill",
                    tint: .red,
                    items: guide.overused,
                    note: "Strengths can be overdone too. Interviewers notice when someone leans on a strength so hard it causes problems."
                )
                section("Common interview questions", systemImage: "questionmark.bubble", tint: .purple, items: guide.sampleQuestions, quoted: true)

                evidence

                if placement.showsBuildStory {
                    Button {
                        router.prepStories(forCompetencies: [competency.name])
                        onClose()
                    } label: {
                        Label("Build a STAR story for this", systemImage: "briefcase")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()
            .frame(maxWidth: DuoLayout.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label(competency.factor.label, systemImage: competency.factor.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(competency.factor.tint)
                Text(competency.name)
                    .font(.title2.bold())
                Text(competency.definition)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private var evidence: some View {
        let record = CompetencyRecord.build(from: entries)[competency.name]
        VStack(alignment: .leading, spacing: 8) {
            Label("My evidence", systemImage: "star.square.on.square")
                .font(.headline)
            if let record, record.days > 0, let best = record.best {
                HStack(spacing: 8) {
                    Chip(text: "\(record.days) day\(record.days == 1 ? "" : "s")")
                    Label("Best: \(best.label)", systemImage: best.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(best.tint)
                }
            } else {
                Text("You haven't shown this in a recap yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if placement.showsEvidenceLink {
                Button {
                    router.showCompetency(competency.name)
                    onClose()
                } label: {
                    Label("See my evidence", systemImage: "chevron.right.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func section(
        _ title: String,
        systemImage: String,
        tint: Color,
        items: [String],
        note: String? = nil,
        quoted: Bool = false
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                BulletList(items: quoted ? items.map { "“\($0)”" } : items)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .leading) {
                // A colored edge, so Skilled, Less skilled, and Overused are easy to tell apart.
                UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14)
                    .fill(tint)
                    .frame(width: 4)
            }
        }
    }
}

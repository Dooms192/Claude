import Charts
import SwiftData
import SwiftUI

/// The Projects tab: projects detected from your recaps, each with an AI overview,
/// highlights, a weekly activity chart, and a day-by-day timeline.
///
/// Uses the same adaptive split as the other tabs: list and detail side by side on the
/// unfolded Duo, one column when folded. The selected project and each project's scroll
/// position live here, above the layout switch, so folding or unfolding never resets them.
struct ProjectsView: View {
    @Query(sort: \Project.lastMentioned, order: .reverse) private var projects: [Project]
    @State private var selection: Project?
    @State private var scrollPositions: [UUID: String] = [:]

    var body: some View {
        AdaptiveSplitView(selection: $selection) {
            ProjectListView(projects: projects, selection: $selection)
        } detail: { project in
            NavigationStack {
                ProjectDetailView(
                    project: project,
                    scrollPosition: scrollBinding(for: project),
                    onRemoved: { selection = nil },
                    onMerged: { selection = $0 }
                )
            }
        } placeholder: {
            ContentUnavailableView(
                "Pick a project",
                systemImage: "square.stack.3d.up",
                description: Text("See its overview, highlights, and every day you worked on it.")
            )
        }
    }

    private func scrollBinding(for project: Project) -> Binding<String?> {
        Binding(
            get: { scrollPositions[project.id] },
            set: { scrollPositions[project.id] = $0 }
        )
    }
}

// MARK: - List

struct ProjectListView: View {
    let projects: [Project]
    @Binding var selection: Project?

    @Environment(\.modelContext) private var context
    @Query(sort: \DayEntry.date, order: .reverse) private var entries: [DayEntry]
    @Query private var ignoredNames: [IgnoredProjectName]

    private func projects(_ status: ProjectStatus) -> [Project] {
        projects.filter { $0.status == status }
    }

    /// New project names from all recaps that are waiting for Add, Rename, Merge, or Ignore.
    private var detections: [ProjectNote] {
        let ignored = Set(ignoredNames.map { $0.name.normalizedKey })
        var seen = Set<String>()
        var result: [ProjectNote] = []
        for entry in entries {
            for detection in entry.projectDetections(existing: projects, ignored: ignored)
            where seen.insert(detection.projectName.normalizedKey).inserted {
                result.append(detection)
            }
        }
        return result
    }

    var body: some View {
        let pending = detections
        List(selection: $selection) {
            if !pending.isEmpty {
                Section("New projects detected") {
                    ForEach(Array(pending.enumerated()), id: \.offset) { _, detection in
                        NewProjectCard(detection: detection, projects: projects)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                }
            }

            section("Active", projects(.active))
            section("Paused", projects(.paused))
            section("Completed", projects(.completed))
            section("Inactive · Still working on these?", projects(.inactive))
        }
        .overlay {
            if projects.isEmpty && pending.isEmpty {
                ContentUnavailableView {
                    Label("No projects yet", systemImage: "square.stack.3d.up")
                } description: {
                    Text("Talk about what you're working on in your daily recap. Recap spots ongoing projects and asks before adding them here.")
                }
            }
        }
        .navigationTitle("Projects")
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Project]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { project in
                    NavigationLink(value: project) {
                        ProjectRow(project: project)
                    }
                    .swipeActions(edge: .trailing) {
                        if project.status != .completed {
                            Button("Done") { project.status = .completed; save() }
                                .tint(.blue)
                        }
                        if project.status == .inactive {
                            Button("Still on it") { ProjectStore.confirmStillWorking(project); save() }
                                .tint(.green)
                        }
                    }
                }
            }
        }
    }

    private func save() { try? context.save() }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            ProjectIcon(project: project)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(project.oneLineStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(project.daysWorked) day\(project.daysWorked == 1 ? "" : "s") · last mentioned \(project.lastMentioned.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

struct ProjectDetailView: View {
    let project: Project
    @Binding var scrollPosition: String?
    var onRemoved: () -> Void
    var onMerged: (Project) -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \Project.name) private var allProjects: [Project]

    @State private var editing = false
    @State private var refreshing = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var mergeTarget: Project?

    /// Overview and highlights sit side by side when there's room (the unfolded Duo in
    /// landscape), and stack when there isn't.
    private let insightColumns = [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header.id("header")

                if project.status == .inactive {
                    stillWorkingCard.id("still-working")
                }

                LazyVGrid(columns: insightColumns, alignment: .leading, spacing: 16) {
                    overviewCard
                    highlightsCard
                }
                .id("insight")

                activityCard.id("activity")

                if !project.relatedGoals.isEmpty {
                    relatedGoalsCard.id("goals")
                }

                Button {
                    router.prepInterview(for: project)
                } label: {
                    Label("Prep interview stories from this project", systemImage: "briefcase")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .id("prep")

                Text("Timeline")
                    .font(.title3.bold())
                    .id("timeline")

                let timeline = project.timeline
                ForEach(timeline) { entry in
                    TimelinePoint(project: project, entry: entry, isLast: entry.id == timeline.last?.id)
                        .id(entry.id.uuidString)
                }
            }
            .scrollTargetLayout()
            .padding()
            .readableWidth()
        }
        // Remembered above the fold/unfold switch, so you land where you left off.
        .scrollPosition(id: $scrollPosition, anchor: .top)
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $editing) { ProjectEditor(project: project) }
        .confirmationDialog(
            "Merge into “\(mergeTarget?.name ?? "")”?",
            isPresented: .init(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Merge") {
                guard let target = mergeTarget else { return }
                onMerged(target)
                ProjectStore.merge(project, into: target, in: context)
                Task { await ProjectInsights.refreshQuietly([target]) }
            }
        } message: {
            Text("Every day from “\(project.name)” moves into “\(mergeTarget?.name ?? "")”, and this project is removed.")
        }
        .confirmationDialog("Delete this project?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onRemoved()
                ProjectStore.delete(project, in: context)
            }
        } message: {
            Text("Your recaps stay in your journal, but this project's daily notes are removed.")
        }
        .alert("Couldn't update the overview", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ProjectIcon(project: project, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name).font(.title.bold())
                    Label(project.status.label, systemImage: project.status.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(project.status.tint)
                }
            }
            if !project.details.isEmpty {
                Text(project.details).foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 6) {
                Chip(text: "\(project.daysWorked) day\(project.daysWorked == 1 ? "" : "s") of work", tint: project.color)
                Chip(text: "Started \(project.startDate.formatted(date: .abbreviated, time: .omitted))", tint: .secondary)
                Chip(text: "Last mentioned \(project.lastMentioned.formatted(.relative(presentation: .named)))", tint: .secondary)
                if let target = project.targetDate {
                    Chip(text: "Target \(target.formatted(date: .abbreviated, time: .omitted))", tint: .orange)
                }
            }
        }
    }

    private var stillWorkingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Still working on this?", systemImage: "moon.zzz")
                .font(.headline)
            Text("You haven't mentioned it in over \(ProjectStore.inactivityDays) days.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                Button("Yes, still on it") { ProjectStore.confirmStillWorking(project); save() }
                    .buttonStyle(.borderedProminent)
                Button("It's done") { project.status = .completed; save() }
                    .buttonStyle(.bordered)
                Button("Pause it") { project.status = .paused; save() }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var overviewCard: some View {
        SectionCard(title: "Overview", systemImage: "text.alignleft") {
            if let insight = project.insight {
                VStack(alignment: .leading, spacing: 12) {
                    Text(insight.summary)
                    labeledList("Done", insight.done, color: .green)
                    labeledList("Current problems", insight.problems, color: .red)
                    labeledList("Next steps", insight.nextSteps, color: .blue)
                    if let updated = project.insightUpdatedAt {
                        Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No overview yet. It's written automatically after your next recap mentions this project, or you can write it now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    refreshButton
                }
            }
        }
    }

    private var highlightsCard: some View {
        SectionCard(title: "Highlights", systemImage: "star") {
            if let insight = project.insight,
               !(insight.wins.isEmpty && insight.skills.isEmpty && insight.blockersSolved.isEmpty) {
                VStack(alignment: .leading, spacing: 12) {
                    labeledList("Key wins", insight.wins, color: .orange)
                    if !insight.skills.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Skills used").font(.subheadline.weight(.semibold))
                            FlowLayout(spacing: 6) {
                                ForEach(insight.skills, id: \.self) { Chip(text: $0, tint: project.color) }
                            }
                        }
                    }
                    if !insight.blockersSolved.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Blockers I solved").font(.subheadline.weight(.semibold))
                            ForEach(Array(insight.blockersSolved.enumerated()), id: \.offset) { _, item in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.blocker).font(.subheadline)
                                    Label(item.resolution, systemImage: "arrow.turn.down.right")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Wins, skills, and solved blockers show up here as the overview fills in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var activityCard: some View {
        let weeks = WeekCount.lastWeeks(from: project.timeline.map(\.date))
        return SectionCard(title: "Activity", systemImage: "chart.bar") {
            Chart(weeks) { week in
                BarMark(
                    x: .value("Week", week.start, unit: .weekOfYear),
                    y: .value("Days", week.days)
                )
                .foregroundStyle(project.color.gradient)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3))
            }
            .frame(height: 140)
            Text("Days you worked on it each week, last 12 weeks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var relatedGoalsCard: some View {
        SectionCard(title: "Related goals", systemImage: "target") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(project.relatedGoals) { goal in
                    Label(goal.title, systemImage: "target")
                        .foregroundStyle(goal.isArchived ? .secondary : .primary)
                }
            }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await refresh() }
        } label: {
            if refreshing {
                ProgressView()
            } else {
                Label("Write overview", systemImage: "sparkles")
            }
        }
        .buttonStyle(.bordered)
        .disabled(refreshing)
    }

    @ViewBuilder
    private func labeledList(_ title: String, _ items: [String], color: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                BulletList(items: items)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh overview", systemImage: "arrow.clockwise")
                }
                .disabled(refreshing)

                Menu {
                    ForEach(ProjectStatus.allCases.filter { $0 != .inactive }) { status in
                        Button {
                            project.status = status
                            save()
                        } label: {
                            Label(status.label, systemImage: status.systemImage)
                        }
                    }
                } label: {
                    Label("Status", systemImage: "flag")
                }

                let others = allProjects.filter { $0.id != project.id }
                if !others.isEmpty {
                    Menu {
                        ForEach(others) { other in
                            Button(other.name) { mergeTarget = other }
                        }
                    } label: {
                        Label("Merge into…", systemImage: "arrow.triangle.merge")
                    }
                }

                ShareLink(item: ProjectExport.text(for: project)) {
                    Label("Share as text", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete project", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: Actions

    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        do {
            try await ProjectInsights.refresh(project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() { try? context.save() }
}

/// One day on the project's vertical timeline. Tap it to open that day's full recap.
private struct TimelinePoint: View {
    let project: Project
    let entry: DayEntry
    let isLast: Bool

    var body: some View {
        let note = project.note(in: entry)
        let signal = note?.signal ?? .progressed
        NavigationLink {
            EntryDetailView(entry: entry) {}
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Image(systemName: signal.systemImage)
                        .font(.title3)
                        .foregroundStyle(signal.tint)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel(signal.label)
                    if !isLast {
                        Rectangle()
                            .fill(.quaternary)
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(signal.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(signal.tint)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(note?.note ?? entry.headline)
                        .multilineTextAlignment(.leading)
                    if let blockers = note?.blockers, !blockers.isEmpty {
                        Text("Blocked by: " + blockers.joined(separator: "; "))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if let next = note?.nextSteps, !next.isEmpty {
                        Text("Next: " + next.joined(separator: "; "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// How many days you worked on a project in one week, for the activity chart.
struct WeekCount: Identifiable {
    let start: Date
    let days: Int
    var id: Date { start }

    static func lastWeeks(from dates: [Date], count: Int = 12, calendar: Calendar = .current) -> [WeekCount] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        return (0..<count).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let end = calendar.date(byAdding: .day, value: 7, to: start)
            else { return nil }
            let days = Set(dates.filter { $0 >= start && $0 < end }).count
            return WeekCount(start: start, days: days)
        }
    }
}

// MARK: - Editor

struct ProjectEditor: View {
    let project: Project

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var details = ""
    @State private var status: ProjectStatus = .active
    @State private var hasTarget = false
    @State private var targetDate = Date()
    @State private var colorName = "indigo"
    @State private var icon = "folder.fill"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project name", text: $name)
                    TextField("Short description (optional)", text: $details, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Picker("Status", selection: $status) {
                        ForEach(ProjectStatus.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Target date", isOn: $hasTarget.animation())
                    if hasTarget {
                        DatePicker("Date", selection: $targetDate, displayedComponents: .date)
                    }
                }
                Section("Color") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ProjectPalette.colorNames, id: \.self) { option in
                                Button {
                                    colorName = option
                                } label: {
                                    Circle()
                                        .fill(ProjectPalette.color(named: option))
                                        .frame(width: 32, height: 32)
                                        .overlay {
                                            if option == colorName {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                        ForEach(ProjectPalette.icons, id: \.self) { option in
                            Button {
                                icon = option
                            } label: {
                                Image(systemName: option)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(option == icon ? .white : .primary)
                                    .background(
                                        option == icon ? ProjectPalette.color(named: colorName) : Color.secondary.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmed.isEmpty)
                }
            }
            .onAppear {
                name = project.name
                details = project.details
                status = project.status
                colorName = project.colorName
                icon = project.icon
                if let target = project.targetDate {
                    hasTarget = true
                    targetDate = target
                }
            }
        }
    }

    private func save() {
        // Renaming also updates the name on every day's note, so the timeline stays intact.
        ProjectStore.rename(project, to: name, in: context)
        project.details = details.trimmed
        project.status = status
        if status == .active { project.stillWorkingConfirmedAt = Date() }
        project.targetDate = hasTarget ? targetDate : nil
        project.colorName = colorName
        project.icon = icon
        try? context.save()
        dismiss()
    }
}

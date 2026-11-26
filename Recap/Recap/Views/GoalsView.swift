import SwiftData
import SwiftUI

struct GoalsView: View {
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @State private var selection: Goal?
    @State private var showingNewGoal = false

    var body: some View {
        AdaptiveSplitView(selection: $selection) {
            GoalListView(goals: goals, selection: $selection, showingNewGoal: $showingNewGoal)
        } detail: { goal in
            GoalDetailView(goal: goal) { selection = nil }
        } placeholder: {
            ContentUnavailableView(
                "Pick a goal",
                systemImage: "target",
                description: Text("See every day you made progress on it.")
            )
        }
        .sheet(isPresented: $showingNewGoal) {
            GoalEditor(goal: nil)
        }
    }
}

struct GoalListView: View {
    let goals: [Goal]
    @Binding var selection: Goal?
    @Binding var showingNewGoal: Bool

    private var active: [Goal] { goals.filter { !$0.isArchived } }
    private var archived: [Goal] { goals.filter(\.isArchived) }

    var body: some View {
        List(selection: $selection) {
            if !active.isEmpty {
                Section("Active") {
                    ForEach(active) { row(for: $0) }
                }
            }
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { row(for: $0) }
                }
            }
        }
        .overlay {
            if goals.isEmpty {
                ContentUnavailableView {
                    Label("No goals yet", systemImage: "target")
                } description: {
                    Text("Add what you're working toward. Each daily recap is checked against your goals, so you can see your progress over time.")
                } actions: {
                    Button("Add a goal") { showingNewGoal = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Goals")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewGoal = true
                } label: {
                    Label("Add goal", systemImage: "plus")
                }
            }
        }
    }

    private func row(for goal: Goal) -> some View {
        NavigationLink(value: goal) {
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title).font(.headline)
                let days = goal.progressEntries
                Text(days.isEmpty
                     ? "No progress recorded yet"
                     : "\(days.count) day\(days.count == 1 ? "" : "s") of progress · last \(days[0].date.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}

struct GoalDetailView: View {
    let goal: Goal
    var onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        let days = goal.progressEntries
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(goal.title).font(.largeTitle.bold())
                    if !goal.details.isEmpty {
                        Text(goal.details).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Chip(text: "\(days.count) day\(days.count == 1 ? "" : "s") of progress")
                        if let target = goal.targetDate {
                            Chip(text: "Target \(target.formatted(date: .abbreviated, time: .omitted))", tint: .orange)
                        }
                        if goal.isArchived { Chip(text: "Archived", tint: .secondary) }
                    }
                }

                if days.isEmpty {
                    SectionCard(title: "No progress yet", systemImage: "clock") {
                        Text("When you mention working on this in a daily recap, it'll show up here.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    SectionCard(title: "Progress", systemImage: "chart.line.uptrend.xyaxis") {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(days) { entry in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 6)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Text(entry.note(for: goal) ?? entry.headline)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .readableWidth()
        }
        .navigationTitle("Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
                    Button {
                        goal.isArchived.toggle()
                        try? context.save()
                    } label: {
                        Label(goal.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $editing) { GoalEditor(goal: goal) }
        .confirmationDialog("Delete this goal?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete()
                context.delete(goal)
                try? context.save()
            }
        } message: {
            Text("Your recaps stay in your journal.")
        }
    }
}

struct GoalEditor: View {
    let goal: Goal?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var hasTarget = false
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Goal, e.g. Lead a project end to end", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Details (optional)", text: $details, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    Toggle("Target date", isOn: $hasTarget.animation())
                    if hasTarget {
                        DatePicker("Date", selection: $targetDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmed.isEmpty)
                }
            }
            .onAppear {
                guard let goal else { return }
                title = goal.title
                details = goal.details
                if let target = goal.targetDate {
                    hasTarget = true
                    targetDate = target
                }
            }
        }
    }

    private func save() {
        // Either way, past recaps that mentioned this goal get linked to it.
        if let goal {
            goal.title = title.titleCased
            goal.details = details.trimmed
            goal.targetDate = hasTarget ? targetDate : nil
            GoalLinker.link(goal, in: context)
        } else {
            GoalLinker.createGoal(
                title: title,
                details: details.trimmed,
                targetDate: hasTarget ? targetDate : nil,
                in: context
            )
        }
        try? context.save()
        dismiss()
    }
}

import SwiftData
import SwiftUI

/// "New project detected: 'X'" with Add, Rename, Merge, and Ignore.
/// Shown after a recap is saved, on the day's recap, and at the top of the Projects tab.
struct NewProjectCard: View {
    let detection: ProjectNote
    /// Existing projects you can merge it into.
    let projects: [Project]

    @Environment(\.modelContext) private var context
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("New project detected: “\(detection.projectName)”")
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
            }
            if !detection.note.isEmpty {
                Text(detection.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 8) {
                Button("Add") { add(named: nil) }
                    .buttonStyle(.borderedProminent)
                Button("Rename") {
                    newName = detection.projectName
                    renaming = true
                }
                .buttonStyle(.bordered)
                Menu("Merge") {
                    ForEach(projects) { project in
                        Button(project.name) { merge(into: project) }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(projects.isEmpty)
                Button("Ignore") {
                    withAnimation { ProjectStore.ignore(detection.projectName, in: context) }
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .alert("Name this project", isPresented: $renaming) {
            TextField("Project name", text: $newName)
            Button("Add") { add(named: newName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func add(named name: String?) {
        if let name, name.trimmed.isEmpty { return }
        let project = withAnimation {
            ProjectStore.create(from: detection, named: name, in: context)
        }
        Task { await ProjectInsights.refreshQuietly([project]) }
    }

    private func merge(into project: Project) {
        withAnimation { ProjectStore.merge(detection: detection, into: project, in: context) }
        Task { await ProjectInsights.refreshQuietly([project]) }
    }
}

/// A small colored tag naming a project, used on journal entries.
struct ProjectTag: View {
    let project: Project

    var body: some View {
        Label(project.name, systemImage: project.icon)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(project.color.opacity(0.16), in: Capsule())
            .foregroundStyle(project.color)
    }
}

/// The project's icon on its color, used in lists and headers.
struct ProjectIcon: View {
    let project: Project
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: project.icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(project.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// What a recap said about each project, on the day's summary.
struct ProjectNotesCard: View {
    let notes: [ProjectNote]
    let projects: [Project]

    var body: some View {
        SectionCard(title: "Projects", systemImage: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    let project = projects.first { $0.name.normalizedKey == note.projectName.normalizedKey }
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: note.signal.systemImage)
                            .foregroundStyle(note.signal.tint)
                            .accessibilityLabel(note.signal.label)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(note.projectName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(project?.color ?? .primary)
                                Text(note.signal.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(note.note)
                            if !note.blockers.isEmpty {
                                Text("Blocked by: " + note.blockers.joined(separator: "; "))
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                            if !note.nextSteps.isEmpty {
                                Text("Next: " + note.nextSteps.joined(separator: "; "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Plain-text export of a project, for performance reviews or résumé updates.
enum ProjectExport {
    @MainActor
    static func text(for project: Project) -> String {
        var lines = [project.name]
        var facts = [
            project.status.label,
            "Started \(DayFormat.iso(project.startDate))",
            "Last worked on \(DayFormat.iso(project.lastMentioned))",
            "\(project.daysWorked) day\(project.daysWorked == 1 ? "" : "s") of work",
        ]
        if let target = project.targetDate { facts.append("Target \(DayFormat.iso(target))") }
        lines.append(facts.joined(separator: " · "))
        if !project.details.isEmpty { lines += ["", project.details] }

        if let insight = project.insight {
            lines += ["", "Overview", insight.summary]
            func list(_ title: String, _ items: [String]) {
                guard !items.isEmpty else { return }
                lines += ["", title] + items.map { "- \($0)" }
            }
            list("Done", insight.done)
            list("Open problems", insight.problems)
            list("Next steps", insight.nextSteps)
            list("Key wins", insight.wins)
            list("Skills", insight.skills)
            list("Blockers solved", insight.blockersSolved.map { "\($0.blocker): \($0.resolution)" })
        }

        lines += ["", "Timeline"]
        for entry in project.timeline.reversed() {
            guard let note = project.note(in: entry) else { continue }
            var line = "\(DayFormat.iso(entry.date)) [\(note.signal.label)] \(note.note)"
            if !note.blockers.isEmpty { line += " Blocked by: " + note.blockers.joined(separator: "; ") + "." }
            if !note.nextSteps.isEmpty { line += " Next: " + note.nextSteps.joined(separator: "; ") + "." }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}

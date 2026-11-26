import SwiftData
import SwiftUI

/// What's selected on the Competencies screen.
enum CompetencySelection: Hashable {
    case coverage
    case competency(String)
}

/// Browse, search, and review your competencies, inside the Interview tab.
///
/// Same adaptive split as every other screen: list on the left and detail on the right on
/// the unfolded Duo, one column when folded. Selection, search text, and re-tagging progress
/// live here, above the layout switch, so folding or unfolding keeps your place.
struct CompetenciesView: View {
    @Query(sort: \DayEntry.date, order: .reverse) private var entries: [DayEntry]
    @Environment(AppRouter.self) private var router

    @State private var selection: CompetencySelection?
    @State private var searchText = ""
    @State private var dictation = RecapRecorder()
    @State private var retagProgress: (done: Int, total: Int)?
    @State private var retagMessage: String?

    var body: some View {
        let records = CompetencyRecord.build(from: entries)
        let untagged = entries.filter { $0.competenciesTaggedAt == nil && !$0.transcript.trimmed.isEmpty }.count

        AdaptiveSplitView(selection: $selection) {
            CompetencyListView(
                selection: $selection,
                records: records,
                untaggedCount: untagged,
                searchText: $searchText,
                dictation: dictation,
                retagProgress: retagProgress,
                onRetag: { Task { await retag() } }
            )
        } detail: { selected in
            NavigationStack {
                switch selected {
                case .coverage:
                    CoverageView(records: records, untaggedCount: untagged, isRetagging: retagProgress != nil) { name in
                        selection = .competency(name)
                    } onRetag: {
                        Task { await retag() }
                    }
                case .competency(let name):
                    if let record = records[name] {
                        CompetencyDetailView(record: record) {
                            router.prepStories(forCompetencies: [name])
                        }
                    }
                }
            }
        } placeholder: {
            ContentUnavailableView(
                "Pick a competency",
                systemImage: "star.square.on.square",
                description: Text("See every day you showed it, or open Coverage to find your gaps.")
            )
        }
        // "See my evidence" in a competency's info pop-up lands here.
        .onChange(of: router.pendingCompetencyDetail, initial: true) { _, name in
            guard let name else { return }
            searchText = ""
            selection = .competency(name)
            router.pendingCompetencyDetail = nil
        }
        .onChange(of: dictation.transcript) { _, spoken in
            if dictation.phase == .recording || dictation.phase == .finishing { searchText = spoken }
        }
        .onChange(of: dictation.phase) { _, phase in
            if phase == .review {
                searchText = dictation.transcript
                dictation.reset()
            }
        }
        .alert("Re-tagging", isPresented: .init(
            get: { retagMessage != nil },
            set: { if !$0 { retagMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(retagMessage ?? "")
        }
    }

    private func retag() async {
        guard retagProgress == nil else { return }
        retagProgress = (0, 0)
        let failures = await CompetencyTagging.tagUntagged(entries) { done, total in
            retagProgress = (done, total)
        }
        retagProgress = nil
        retagMessage = failures == 0
            ? "Your past recaps are tagged."
            : "\(failures) recap\(failures == 1 ? "" : "s") couldn't be tagged. You can try again later."
    }
}

// MARK: - List

struct CompetencyListView: View {
    /// Tapping a row sets this, which shows its detail (beside the list when unfolded,
    /// pushed when folded), the same way every other tab works.
    @Binding var selection: CompetencySelection?
    let records: [String: CompetencyRecord]
    let untaggedCount: Int
    @Binding var searchText: String
    /// Meaning-based results from the background search, for the current text.
    @State private var searchResults: [String] = []
    let dictation: RecapRecorder
    let retagProgress: (done: Int, total: Int)?
    let onRetag: () -> Void

    private var isDictating: Bool { dictation.phase == .recording || dictation.phase == .finishing }

    var body: some View {
        let all = Array(records.values)
        List(selection: $selection) {
            InterviewModePicker()

            if untaggedCount > 0 {
                Section {
                    RetagBanner(untaggedCount: untaggedCount, progress: retagProgress, onRetag: onRetag)
                }
            }

            if searchText.trimmed.isEmpty {
                Section {
                    NavigationLink(value: CompetencySelection.coverage) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Coverage").font(.headline)
                                Text("\(all.filter { $0.coverage == .strong }.count) strong · \(all.filter { $0.coverage == .thin }.count) thin · \(all.filter { $0.coverage == .none }.count) none")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "chart.bar.doc.horizontal").foregroundStyle(Color.accentColor)
                        }
                    }
                }
                ForEach(CompetencyFactor.allCases) { factor in
                    Section {
                        ForEach(CompetencyLibrary.competencies(in: factor)) { competency in
                            row(for: competency)
                        }
                    } header: {
                        Label(factor.label, systemImage: factor.systemImage)
                            .foregroundStyle(factor.tint)
                    }
                }
            } else {
                Section("Best matches") {
                    ForEach(CompetencySearch.matches(for: searchText, results: searchResults)) { competency in
                        row(for: competency)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search, like \"handling conflict\"")
        .task(id: searchText) {
            let results = await CompetencySearch.results(for: searchText)
            if !Task.isCancelled { searchResults = results }
        }
        // Load the language model in the background, so the first search is quick too.
        .task { await CompetencySearchIndex.shared.warmUp() }
        .navigationTitle("Competencies")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        if dictation.phase == .recording { await dictation.stop() } else { await dictation.start() }
                    }
                } label: {
                    Label(isDictating ? "Stop" : "Say it", systemImage: isDictating ? "stop.fill" : "mic.fill")
                }
                .tint(isDictating ? .red : nil)
                .disabled(dictation.phase == .finishing)
            }
        }
    }

    private func row(for competency: Competency) -> some View {
        let record = records[competency.name]
        return NavigationLink(value: CompetencySelection.competency(competency.name)) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(competency.name).font(.body.weight(.medium))
                    if let record, record.days > 0, let best = record.best {
                        Text("\(record.days) day\(record.days == 1 ? "" : "s") · best example \(best.label.lowercased())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No examples yet")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
                if let best = record?.best {
                    Image(systemName: best.systemImage)
                        .foregroundStyle(best.tint)
                        .accessibilityLabel("Best example: \(best.label)")
                }
                if selection == .competency(competency.name) {
                    CompetencyInfoButton(competency: competency)
                }
            }
        }
    }
}

/// The Prep / Competencies switch at the top of both Interview screens.
struct InterviewModePicker: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        Section {
            Picker("Interview", selection: $router.interviewMode) {
                Text("Prep").tag(InterviewMode.prep)
                Text("Competencies").tag(InterviewMode.competencies)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }
}

private struct RetagBanner: View {
    let untaggedCount: Int
    let progress: (done: Int, total: Int)?
    let onRetag: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(untaggedCount) recap\(untaggedCount == 1 ? " hasn't" : "s haven't") been tagged with competencies yet.")
                .font(.subheadline)
            if let progress {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                    Text("Tagging \(min(progress.done + 1, max(progress.total, 1))) of \(max(progress.total, 1))…")
                        .font(.caption)
                }
            } else {
                Button("Re-tag my past recaps", action: onRetag)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Detail

struct CompetencyDetailView: View {
    let record: CompetencyRecord
    var onBuildStory: () -> Void

    private var competency: Competency { record.competency }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(competency.factor.label, systemImage: competency.factor.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(competency.factor.tint)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(competency.name).font(.largeTitle.bold())
                        CompetencyInfoButton(competency: competency, placement: .detailScreen)
                            .font(.title2)
                    }
                    Text(competency.definition)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                SectionCard(title: "What it looks like", systemImage: "eye") {
                    BulletList(items: competency.signals)
                }

                Button(action: onBuildStory) {
                    Label("Build a STAR story for this competency", systemImage: "briefcase")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if record.evidence.isEmpty {
                    SectionCard(title: "No examples yet", systemImage: "magnifyingglass") {
                        Text("None of your recaps show this yet. Watch for moments like these in your day, and mention them in your recap:")
                            .foregroundStyle(.secondary)
                        BulletList(items: competency.signals)
                    }
                } else {
                    Text("Your evidence · \(record.days) day\(record.days == 1 ? "" : "s")")
                        .font(.title3.bold())
                    ForEach(record.evidence) { item in
                        NavigationLink {
                            EntryDetailView(entry: item.entry) {}
                        } label: {
                            EvidenceRow(evidence: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .readableWidth()
        }
        .navigationTitle(competency.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EvidenceRow: View {
    let evidence: CompetencyEvidence

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(evidence.entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Label(evidence.tag.level.label, systemImage: evidence.tag.level.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(evidence.tag.level.tint)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            Text(evidence.tag.moment)
                .multilineTextAlignment(.leading)
            let projects = evidence.entry.projects ?? []
            if !projects.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(projects) { ProjectTag(project: $0) }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: - Coverage

/// Which competencies you have strong stories for, which are thin, and which have none.
struct CoverageView: View {
    let records: [String: CompetencyRecord]
    let untaggedCount: Int
    let isRetagging: Bool
    var onSelect: (String) -> Void
    var onRetag: () -> Void

    var body: some View {
        let all = CompetencyLibrary.all.compactMap { records[$0.name] }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Coverage").font(.largeTitle.bold())
                Text("Strong means at least one day where you clearly led or drove it. Thin means only lighter examples. Use the gaps as things to watch for, or work on, in your daily work.")
                    .foregroundStyle(.secondary)

                if untaggedCount > 0 {
                    Button(action: onRetag) {
                        Label(isRetagging ? "Tagging…" : "Re-tag my past recaps (\(untaggedCount))", systemImage: "tag")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRetagging)
                }

                group("Strong stories", systemImage: "star.fill", tint: .orange, records: all.filter { $0.coverage == .strong })
                group("Thin", systemImage: "star.leadinghalf.filled", tint: .blue, records: all.filter { $0.coverage == .thin })
                group("No examples yet", systemImage: "star", tint: .secondary, records: all.filter { $0.coverage == .none })
            }
            .padding()
            .readableWidth()
        }
        .navigationTitle("Coverage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: CompetencyExport.text(records: all)) {
                    Label("Export best examples", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, systemImage: String, tint: Color, records: [CompetencyRecord]) -> some View {
        SectionCard(title: "\(title) · \(records.count)", systemImage: systemImage) {
            if records.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(records, id: \.competency.name) { record in
                        Button {
                            onSelect(record.competency.name)
                        } label: {
                            Chip(text: record.competency.name, tint: tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Your best example for each competency as text, to review before an interview.
enum CompetencyExport {
    @MainActor
    static func text(records: [CompetencyRecord]) -> String {
        var lines = ["My best example for each competency", ""]
        for factor in CompetencyFactor.allCases {
            lines.append(factor.label.uppercased())
            for record in records where record.competency.factor == factor {
                if let best = record.evidence.first {
                    lines.append("\(record.competency.name) (\(best.tag.level.label), \(record.days) day\(record.days == 1 ? "" : "s"))")
                    lines.append("  \(DayFormat.iso(best.entry.date)): \(best.tag.moment)")
                    if !best.entry.summary.isEmpty { lines.append("  That day: \(best.entry.summary)") }
                } else {
                    lines.append("\(record.competency.name): no example yet")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Tags on a recap

/// The competencies a recap showed, as chips grouped by factor. Long-press a chip to
/// remove it, or use Edit to add one by hand.
struct CompetencyTagsCard: View {
    let entry: DayEntry

    @Environment(\.modelContext) private var context
    @State private var editing = false
    @State private var tagging = false
    @State private var errorMessage: String?

    var body: some View {
        SectionCard(title: "Competencies", systemImage: "star.square.on.square") {
            VStack(alignment: .leading, spacing: 12) {
                if entry.competencyTags.isEmpty {
                    if entry.competenciesTaggedAt == nil {
                        Text("This recap hasn't been tagged yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await tag() }
                        } label: {
                            if tagging { ProgressView() } else { Label("Tag competencies", systemImage: "sparkles") }
                        }
                        .buttonStyle(.bordered)
                        .disabled(tagging)
                    } else {
                        Text("No competencies stood out on this day.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(CompetencyFactor.allCases) { factor in
                        let tags = entry.competencyTags.filter { $0.definition?.factor == factor }
                        if !tags.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(factor.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(factor.tint)
                                FlowLayout(spacing: 6) {
                                    ForEach(tags, id: \.competency) { tag in
                                        CompetencyChip(tag: tag, tint: factor.tint)
                                            .contextMenu {
                                                Text(tag.moment)
                                                Button(role: .destructive) {
                                                    remove(tag)
                                                } label: {
                                                    Label("Remove tag", systemImage: "minus.circle")
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }
                }
                Button("Edit competencies") { editing = true }
                    .font(.subheadline)
            }
        }
        .sheet(isPresented: $editing) { CompetencyTagEditor(entry: entry) }
        .alert("Couldn't tag", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func remove(_ tag: CompetencyTag) {
        withAnimation { entry.competencyTags.removeAll { $0.competency == tag.competency } }
        try? context.save()
    }

    private func tag() async {
        tagging = true
        defer { tagging = false }
        do {
            try await CompetencyTagging.tag(entry)
            try? context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CompetencyChip: View {
    let tag: CompetencyTag
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tag.level.systemImage)
                .font(.caption2)
            Text(tag.competency)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.14), in: Capsule())
        .foregroundStyle(tint)
        .accessibilityLabel("\(tag.competency), \(tag.level.label)")
    }
}

/// Remove wrong tags or add one by hand.
struct CompetencyTagEditor: View {
    let entry: DayEntry

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var tags: [CompetencyTag] = []
    @State private var newCompetency = CompetencyLibrary.all[0].name
    @State private var newMoment = ""
    @State private var newStrength: CompetencyStrength = .solid

    var body: some View {
        NavigationStack {
            Form {
                Section("Tagged on this day") {
                    if tags.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    }
                    ForEach(tags, id: \.competency) { tag in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(tag.competency).font(.headline)
                                if let competency = CompetencyLibrary.find(tag.competency) {
                                    CompetencyInfoButton(competency: competency, placement: .insideSheet)
                                }
                                Spacer()
                                Label(tag.level.label, systemImage: tag.level.systemImage)
                                    .font(.caption)
                                    .foregroundStyle(tag.level.tint)
                            }
                            Text(tag.moment).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { tags.remove(atOffsets: $0) }
                }

                Section {
                    Picker("Competency", selection: $newCompetency) {
                        ForEach(CompetencyFactor.allCases) { factor in
                            Section(factor.label) {
                                ForEach(CompetencyLibrary.competencies(in: factor)) { competency in
                                    Text(competency.name).tag(competency.name)
                                }
                            }
                        }
                    }
                    TextField("The moment that shows it", text: $newMoment, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Strength", selection: $newStrength) {
                        ForEach(CompetencyStrength.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button("Add tag") {
                        tags.removeAll { $0.competency == newCompetency }
                        tags.append(CompetencyTag(
                            competency: newCompetency,
                            moment: newMoment.trimmed,
                            strength: newStrength.rawValue,
                            isManual: true
                        ))
                        newMoment = ""
                    }
                    .disabled(newMoment.trimmed.isEmpty)
                } header: {
                    Text("Add a competency")
                } footer: {
                    Text(newStrength.detail)
                }
            }
            .navigationTitle("Competencies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        entry.competencyTags = tags
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .onAppear { tags = entry.competencyTags }
        }
    }
}

// MARK: - Picker for interview prep

/// Choose several competencies to build stories for.
struct CompetencyPickerSheet: View {
    @Binding var selection: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [String] = []

    var body: some View {
        NavigationStack {
            List {
                if searchText.trimmed.isEmpty {
                    ForEach(CompetencyFactor.allCases) { factor in
                        Section(factor.label) {
                            ForEach(CompetencyLibrary.competencies(in: factor)) { row(for: $0) }
                        }
                    }
                } else {
                    Section("Best matches") {
                        ForEach(CompetencySearch.matches(for: searchText, results: searchResults)) { row(for: $0) }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search, like \"leading without authority\"")
            .task(id: searchText) {
                let results = await CompetencySearch.results(for: searchText)
                if !Task.isCancelled { searchResults = results }
            }
            .task { await CompetencySearchIndex.shared.warmUp() }
            .navigationTitle("Build stories for")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !selection.isEmpty {
                        Button("Clear") { selection.removeAll() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(for competency: Competency) -> some View {
        let isSelected = selection.contains(competency.name)
        return HStack(spacing: 12) {
            Button {
                if isSelected {
                    selection.removeAll { $0 == competency.name }
                } else {
                    selection.append(competency.name)
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(competency.name).foregroundStyle(.primary)
                        Text(competency.definition)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            // Borderless so the row's two buttons stay separate tap targets.
            .buttonStyle(.borderless)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            CompetencyInfoButton(competency: competency, placement: .insideSheet)
        }
    }
}

/// The recorder's rotating hint, nudging you toward competencies you have thin evidence for.
enum CompetencyNudge {
    @MainActor
    static func today(entries: [DayEntry], date: Date = Date()) -> String? {
        let records = CompetencyRecord.build(from: entries)
        let thin = CompetencyLibrary.all.filter { records[$0.name]?.coverage != .strong }
        guard !thin.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        return thin[day % thin.count].nudge
    }
}

/// Glue between search boxes and the background search index.
enum CompetencySearch {
    /// Waits for a short pause in typing (the calling task restarts on every keystroke),
    /// then runs the meaning-based search off the main thread.
    static func results(for text: String) async -> [String] {
        guard !text.trimmed.isEmpty else { return [] }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return [] }
        return await CompetencySearchIndex.shared.search(text)
    }

    /// Meaning-based results when they're ready, otherwise instant word matches.
    static func matches(for text: String, results: [String]) -> [Competency] {
        let found = results.compactMap { CompetencyLibrary.find($0) }
        return found.isEmpty ? CompetencyLibrary.quickSearch(text) : found
    }
}

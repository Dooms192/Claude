import SwiftData
import SwiftUI

struct JournalView: View {
    @Query(sort: \DayEntry.date, order: .reverse) private var entries: [DayEntry]
    @State private var selection: DayEntry?
    @State private var searchText = ""

    var body: some View {
        AdaptiveSplitView(selection: $selection) {
            EntryListView(entries: entries, selection: $selection, searchText: $searchText)
        } detail: { entry in
            EntryDetailView(entry: entry) {
                selection = nil
            }
        } placeholder: {
            ContentUnavailableView(
                "Pick a day",
                systemImage: "book.pages",
                description: Text("Choose a recap from the list, or record today's.")
            )
        }
    }
}

private struct MonthSection: Identifiable {
    let month: Date
    let entries: [DayEntry]
    var id: Date { month }
}

struct EntryListView: View {
    let entries: [DayEntry]
    @Binding var selection: DayEntry?
    @Binding var searchText: String
    @Environment(AppRouter.self) private var router

    private var filtered: [DayEntry] {
        EntrySearch.filter(entries, text: searchText)
    }

    private var sections: [MonthSection] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filtered) { entry in
            calendar.date(from: calendar.dateComponents([.year, .month], from: entry.date)) ?? entry.date
        }
        return groups.keys.sorted(by: >).map { month in
            MonthSection(month: month, entries: (groups[month] ?? []).sorted { $0.date > $1.date })
        }
    }

    private var hasRecapToday: Bool {
        entries.contains { $0.date == DayEntry.recapDay(for: Date()) }
    }

    var body: some View {
        List(selection: $selection) {
            // With no recaps at all, the empty-state message below has its own record
            // button, so the card is hidden to keep the two from overlapping.
            if !entries.isEmpty && !hasRecapToday && searchText.isEmpty {
                Section {
                    Button {
                        router.startRecap()
                    } label: {
                        RecordTodayCard()
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            ForEach(sections) { section in
                Section(section.month.formatted(.dateTime.month(.wide).year())) {
                    ForEach(section.entries) { entry in
                        NavigationLink(value: entry) {
                            EntryRow(entry: entry)
                        }
                    }
                }
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("No recaps yet", systemImage: "mic")
                } description: {
                    Text("At the end of each day, talk through what you did. Recap writes it up and keeps it for your next interview.")
                } actions: {
                    Button("Record your first recap") { router.startRecap() }
                        .buttonStyle(.borderedProminent)
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, prompt: "Search your days")
        .navigationTitle("Journal")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.startRecap()
                } label: {
                    Label("Record recap", systemImage: "mic.fill")
                }
            }
        }
    }
}

private struct RecordTodayCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Record today's recap")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("Just talk. Recap writes it up for you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct EntryRow: View {
    let entry: DayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !entry.isSummarized {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Not summarized")
                }
            }
            Text(entry.displayTitle)
                .font(.headline)
                .lineLimit(2)
            Text(entry.isSummarized ? entry.summary : entry.transcript)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct EntryDetailView: View {
    let entry: DayEntry
    var onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var goals: [Goal]
    @State private var isSummarizing = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(DayFormat.long(entry.date))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.displayTitle)
                        .font(.largeTitle.bold())
                }

                EntrySummaryContent(entry: entry)

                if !entry.isSummarized || isSummarizing {
                    Button {
                        Task { await summarize() }
                    } label: {
                        if isSummarizing {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label("Summarize this recap", systemImage: "sparkles").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSummarizing)
                }

                DisclosureGroup("What I said") {
                    Text(entry.transcript)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if entry.isSummarized {
                    Text("Summarized by \(entry.summarizedBy)")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .readableWidth()
        }
        .navigationTitle(entry.date.formatted(.dateTime.month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Task { await summarize() }
                    } label: {
                        Label("Summarize again", systemImage: "arrow.clockwise")
                    }
                    .disabled(isSummarizing)
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete recap", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this recap?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete()
                context.delete(entry)
                try? context.save()
            }
        } message: {
            Text("This can't be undone.")
        }
        .alert("Couldn't summarize", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func summarize() async {
        isSummarizing = true
        defer { isSummarizing = false }
        do {
            try await RecapProcessor.summarize(entry, goals: goals)
            try? context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

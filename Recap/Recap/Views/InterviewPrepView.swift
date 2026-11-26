import SwiftData
import SwiftUI

/// Describe the interview, and Recap searches every day you've recorded and builds
/// STAR stories (Situation, Task, Action, Result) you can tell.
struct InterviewPrepView: View {
    @Query(sort: \PrepSession.createdAt, order: .reverse) private var sessions: [PrepSession]
    @Query(sort: \DayEntry.date, order: .reverse) private var entries: [DayEntry]
    @Environment(\.modelContext) private var context

    // Kept here, above the adaptive layout, so an in-progress request survives a fold or unfold.
    @State private var selection: PrepSession?
    @State private var request = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private static let examples = [
        "Behavioral interview for a product manager role. They care about leadership and handling conflict.",
        "Tell me about a time you failed and what you learned.",
        "Software engineer interview: walk me through a hard technical problem you solved.",
        "Manager role: how I've coached and grown people on my team.",
    ]

    var body: some View {
        AdaptiveSplitView(selection: $selection) {
            List(selection: $selection) {
                Section {
                    TextField(
                        "What's the interview for, and what do they want to hear about?",
                        text: $request,
                        axis: .vertical
                    )
                    .lineLimit(3...8)

                    Button {
                        Task { await prepare() }
                    } label: {
                        HStack {
                            if isWorking {
                                ProgressView()
                                Text("Searching \(entries.count) days…")
                            } else {
                                Image(systemName: "sparkles")
                                Text("Prepare my stories")
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(request.trimmed.isEmpty || isWorking)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Your interview")
                } footer: {
                    Text("\(entries.count) recaps recorded. Uses \(AIConfig.interviewEngine.name) (change in Settings).")
                }

                if request.isEmpty && sessions.isEmpty {
                    Section("Try one of these") {
                        ForEach(Self.examples, id: \.self) { example in
                            Button(example) { request = example }
                                .font(.subheadline)
                        }
                    }
                }

                if !sessions.isEmpty {
                    Section("Past prep") {
                        ForEach(sessions) { session in
                            NavigationLink(value: session) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.query)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(2)
                                    Text("\(session.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(session.engine)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Interview Prep")
        } detail: { session in
            PrepResultView(session: session)
        } placeholder: {
            STARExplainer()
        }
        .alert("Couldn't prepare", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func prepare() async {
        let query = request.trimmed
        guard !query.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let outcome = try await InterviewCoach.prepare(for: query, entries: entries)
            let session = PrepSession(
                query: query,
                engine: outcome.engine,
                note: outcome.note,
                entriesUsed: outcome.entriesUsed,
                prep: outcome.prep
            )
            context.insert(session)
            try? context.save()
            request = ""
            selection = session
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            if selection == session { selection = nil }
            context.delete(session)
        }
        try? context.save()
    }
}

struct PrepResultView: View {
    let session: PrepSession

    var body: some View {
        ScrollView {
            if let prep = session.prep {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.query)
                            .font(.title2.bold())
                        Text("Drew on \(session.entriesUsed) of your days · \(session.engine)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let note = session.note {
                        Label(note, systemImage: "info.circle")
                            .font(.subheadline)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }

                    Text(prep.overview)

                    ForEach(Array(prep.stories.enumerated()), id: \.offset) { index, story in
                        STARStoryCard(number: index + 1, story: story)
                    }

                    if !prep.tips.isEmpty {
                        SectionCard(title: "Tips for this interview", systemImage: "lightbulb") {
                            BulletList(items: prep.tips)
                        }
                    }
                }
                .padding()
                .readableWidth()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: prep.plainText) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            } else {
                ContentUnavailableView("Couldn't open this prep", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle("Your Stories")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One interview story, laid out as Situation, Task, Action, Result.
/// On the wide unfolded screen the four parts sit in a 2×2 grid; folded, they stack.
struct STARStoryCard: View {
    let number: Int
    let story: STARStory
    @State private var showScript = true

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(number)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor, in: Circle())
                Text(story.title)
                    .font(.title3.bold())
            }
            Text(story.whyItFits)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                STARPart(letter: "S", name: "Situation", text: story.situation, tint: .blue)
                STARPart(letter: "T", name: "Task", text: story.task, tint: .purple)
                STARPart(letter: "A", name: "Action", text: story.action, tint: .orange)
                STARPart(letter: "R", name: "Result", text: story.result, tint: .green)
            }

            DisclosureGroup(isExpanded: $showScript) {
                Text("“\(story.howToSayIt)”")
                    .italic()
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            } label: {
                Label("How to say it", systemImage: "quote.bubble")
                    .font(.subheadline.weight(.semibold))
            }

            if !story.dates.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(story.dates, id: \.self) { Chip(text: $0, tint: .secondary) }
                }
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct STARPart: View {
    let letter: String
    let name: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(letter)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(tint, in: RoundedRectangle(cornerRadius: 6))
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Shown on the right side of the unfolded screen before you pick a prep.
struct STARExplainer: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Interview stories from your own days")
                    .font(.title.bold())
                Text("Describe the interview on the left. Recap searches every recap you've recorded, picks the most relevant moments, and turns them into STAR stories:")
                    .foregroundStyle(.secondary)
                STARPart(letter: "S", name: "Situation", text: "The context. Where you were and what was going on.", tint: .blue)
                STARPart(letter: "T", name: "Task", text: "What you were responsible for.", tint: .purple)
                STARPart(letter: "A", name: "Action", text: "The specific steps you took.", tint: .orange)
                STARPart(letter: "R", name: "Result", text: "What happened, ideally with numbers.", tint: .green)
                Text("Every story uses only what you actually said, with the dates it came from.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .readableWidth()
        }
    }
}

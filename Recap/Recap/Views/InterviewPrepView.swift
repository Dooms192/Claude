import SwiftData
import SwiftUI

/// Describe the interview, and Recap searches every day you've recorded and builds
/// STAR stories (Situation, Task, Action, Result) you can tell.
struct InterviewPrepView: View {
    @Query(sort: \PrepSession.createdAt, order: .reverse) private var sessions: [PrepSession]
    @Query(sort: \DayEntry.date, order: .reverse) private var entries: [DayEntry]
    @Query(sort: \Project.lastMentioned, order: .reverse) private var projects: [Project]
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    // Kept here, above the adaptive layout, so an in-progress request survives a fold or unfold.
    @State private var selection: PrepSession?
    @State private var request = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    /// "Use stories from": nil means all projects.
    @State private var projectFilterID: UUID?

    private var selectedProject: Project? {
        projects.first { $0.id == projectFilterID }
    }
    /// Lets you speak the interview description instead of typing it. Same on-device
    /// speech-to-text as daily recaps; the words land in the text box so you can fix them.
    @State private var dictation = RecapRecorder()
    @State private var textBeforeDictation = ""

    // Competencies to build one story each for.
    @State private var selectedCompetencies: [String] = []
    /// Competencies found in what you typed or said, waiting for you to confirm or remove.
    @State private var detectedCompetencies: [String] = []
    @State private var dismissedCompetencies: Set<String> = []
    @State private var lastDetectedText = ""
    @State private var showingCompetencyPicker = false
    @State private var showingPostingSheet = false
    @State private var postingText = ""
    @State private var readingPosting = false

    private var suggestedCompetencies: [String] {
        detectedCompetencies.filter { !selectedCompetencies.contains($0) && !dismissedCompetencies.contains($0) }
    }

    private var canPrepare: Bool {
        !(request.trimmed.isEmpty && selectedCompetencies.isEmpty) && !isWorking && !isDictating
    }

    private var isDictating: Bool {
        dictation.phase == .recording || dictation.phase == .finishing
    }

    private static let examples = [
        "Behavioral interview for a product manager role. They care about leadership and handling conflict.",
        "Tell me about a time you failed and what you learned.",
        "Software engineer interview: walk me through a hard technical problem you solved.",
        "Manager role: how I've coached and grown people on my team.",
    ]

    var body: some View {
        AdaptiveSplitView(selection: $selection) {
            List(selection: $selection) {
                InterviewModePicker()

                Section {
                    if !projects.isEmpty {
                        Picker("Use stories from", selection: $projectFilterID) {
                            Text("All projects").tag(UUID?.none)
                            ForEach(projects) { project in
                                Label(project.name, systemImage: project.icon).tag(Optional(project.id))
                            }
                        }
                    }
                    TextField(
                        "What's the interview for, and what do they want to hear about?",
                        text: $request,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                    .disabled(isDictating)

                    if isDictating {
                        Label("Listening… tap the mic when you're done", systemImage: "waveform")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                            .symbolEffect(.variableColor.iterative, isActive: true)
                    }

                    competencyRow

                    HStack(spacing: 10) {
                        Button {
                            Task { await toggleDictation() }
                        } label: {
                            Image(systemName: isDictating ? "stop.fill" : "mic.fill")
                                .font(.title3)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.bordered)
                        .tint(isDictating ? .red : .accentColor)
                        .controlSize(.large)
                        .disabled(isWorking || dictation.phase == .finishing)
                        .accessibilityLabel(isDictating ? "Stop dictation" : "Speak instead of typing")

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
                        .disabled(!canPrepare)
                    }
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
                                    if !session.competencyNames.isEmpty {
                                        Text(session.competencyNames.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(Color.accentColor)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }

                // Shown in the list itself, so it's visible on every iPhone, folded or not.
                // (On the unfolded Duo it's also on the right until you pick a prep.)
                Section {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recap turns the days you've recorded into stories in this shape:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            STARPart(letter: "S", name: "Situation", text: "The context. Where you were and what was going on.", tint: .blue)
                            STARPart(letter: "T", name: "Task", text: "What you were responsible for.", tint: .purple)
                            STARPart(letter: "A", name: "Action", text: "The specific steps you took.", tint: .orange)
                            STARPart(letter: "R", name: "Result", text: "What happened, ideally with numbers.", tint: .green)
                            Text("Every story uses only what you actually said, with the dates it came from.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    } label: {
                        Label("What's a STAR story?", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("Interview Prep")
        } detail: { session in
            PrepResultView(session: session)
        } placeholder: {
            STARExplainer()
        }
        // "Prep interview stories from this project" on a project page lands here.
        .onAppear(perform: takeProjectFromRouter)
        .onChange(of: router.interviewProjectID) { takeProjectFromRouter() }
        // "Build a STAR story for this competency" lands here.
        .onAppear(perform: takeCompetenciesFromRouter)
        .onChange(of: router.interviewCompetencies) { takeCompetenciesFromRouter() }
        // Finds competencies in your description a moment after you stop typing or talking.
        .task(id: request) { await detectCompetencies() }
        .sheet(isPresented: $showingCompetencyPicker) {
            CompetencyPickerSheet(selection: $selectedCompetencies)
        }
        .sheet(isPresented: $showingPostingSheet) { postingSheet }
        .onChange(of: dictation.transcript) { _, spoken in
            guard isDictating else { return }
            request = Self.join(textBeforeDictation, spoken)
        }
        .onChange(of: dictation.phase) { _, phase in
            // Finished talking: keep the words in the text box and reset for next time.
            if phase == .review {
                request = Self.join(textBeforeDictation, dictation.transcript)
                dictation.reset()
            }
        }
        .onDisappear {
            if dictation.phase == .recording { Task { await dictation.stop() } }
        }
        .alert("Microphone", isPresented: .init(
            get: { dictation.errorMessage != nil },
            set: { if !$0 { dictation.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dictation.errorMessage ?? "")
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
        let competencies = selectedCompetencies
        guard !query.isEmpty || !competencies.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let outcome = try await InterviewCoach.prepare(
                for: query,
                entries: entries,
                project: selectedProject,
                competencies: competencies
            )
            let session = PrepSession(
                query: query.isEmpty ? "Stories for: " + competencies.joined(separator: ", ") : query,
                engine: outcome.engine,
                note: outcome.note,
                entriesUsed: outcome.entriesUsed,
                prep: outcome.prep,
                projectName: selectedProject?.name,
                competencyNames: competencies
            )
            context.insert(session)
            try? context.save()
            request = ""
            selectedCompetencies = []
            detectedCompetencies = []
            dismissedCompetencies = []
            selection = session
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func takeProjectFromRouter() {
        guard let id = router.interviewProjectID else { return }
        projectFilterID = id
        selection = nil
        router.interviewProjectID = nil
    }

    private func takeCompetenciesFromRouter() {
        guard let names = router.interviewCompetencies else { return }
        for name in names where !selectedCompetencies.contains(name) {
            selectedCompetencies.append(name)
        }
        selection = nil
        router.interviewCompetencies = nil
    }

    /// Waits for a pause in typing (this task restarts on every change), then asks the AI
    /// which competencies the description mentions or implies.
    private func detectCompetencies() async {
        let text = request.trimmed
        guard text.count >= 25, text.count <= 1500, text != lastDetectedText, !isDictating else { return }
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled else { return }
        if let found = try? await CompetencyDetection.detect(in: text, isJobPosting: false), !Task.isCancelled {
            lastDetectedText = text
            detectedCompetencies = found
        }
    }

    /// Reads a pasted job posting and pre-selects the 3 to 5 competencies it emphasizes.
    private func readPosting() async {
        let posting = postingText.trimmed
        guard !posting.isEmpty else { return }
        readingPosting = true
        defer { readingPosting = false }
        do {
            let found = try await CompetencyDetection.detect(in: posting, isJobPosting: true)
            for name in found where !selectedCompetencies.contains(name) {
                selectedCompetencies.append(name)
            }
            if request.trimmed.isEmpty {
                lastDetectedText = "Job posting:\n" + posting
                request = lastDetectedText
            }
            postingText = ""
            showingPostingSheet = false
        } catch {
            showingPostingSheet = false
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var competencyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Build stories for")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Choose") { showingCompetencyPicker = true }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            }
            if selectedCompetencies.isEmpty {
                Text("Optional. Pick competencies, paste a job posting, or let Recap find them in your description.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(selectedCompetencies, id: \.self) { name in
                        Button {
                            selectedCompetencies.removeAll { $0 == name }
                        } label: {
                            Label(name, systemImage: "xmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.accentColor.opacity(0.16), in: Capsule())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(name)")
                    }
                }
            }
            if !suggestedCompetencies.isEmpty {
                Text("Found in your description. Tap to add:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(suggestedCompetencies, id: \.self) { name in
                        HStack(spacing: 2) {
                            Button {
                                selectedCompetencies.append(name)
                            } label: {
                                Label(name, systemImage: "plus.circle.fill")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                            Button {
                                dismissedCompetencies.insert(name)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .padding(4)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Not \(name)")
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, 4)
                        .padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                }
            }
            Button {
                showingPostingSheet = true
            } label: {
                Label("Paste a job posting", systemImage: "doc.on.clipboard")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var postingSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste the job description. Recap picks the 3 to 5 competencies it emphasizes and selects them for you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $postingText)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
            .navigationTitle("Job posting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingPostingSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if readingPosting {
                        ProgressView()
                    } else {
                        Button("Find competencies") { Task { await readPosting() } }
                            .disabled(postingText.trimmed.isEmpty)
                    }
                }
            }
        }
    }

    private func toggleDictation() async {
        if dictation.phase == .recording {
            await dictation.stop()
        } else {
            textBeforeDictation = request.trimmed
            await dictation.start()
        }
    }

    private static func join(_ a: String, _ b: String) -> String {
        let a = a.trimmed, b = b.trimmed
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
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
                        Text("Drew on \(session.entriesUsed) of your days\(session.projectName.map { " from “\($0)”" } ?? "") · \(session.engine)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !session.competencyNames.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(session.competencyNames, id: \.self) { Chip(text: $0) }
                            }
                        }
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
    @State private var showFollowUps = false

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let name = story.competency {
                let competency = CompetencyLibrary.find(name)
                Label(name, systemImage: competency?.factor.systemImage ?? "star.square.on.square")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(competency?.factor.tint ?? Color.accentColor)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(number)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor, in: Circle())
                Text(story.title)
                    .font(.title3.bold())
            }
            Text(story.competency == nil ? story.whyItFits : "Why this example: \(story.whyItFits)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let gap = story.gapAdvice {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No strong example yet").font(.subheadline.weight(.semibold))
                        Text(gap).font(.subheadline)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

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

            if let followUps = story.followUps, !followUps.isEmpty {
                DisclosureGroup(isExpanded: $showFollowUps) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(followUps.enumerated()), id: \.offset) { _, followUp in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(followUp.question).font(.subheadline.weight(.semibold))
                                Text(followUp.howToAnswer).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                } label: {
                    Label("Likely follow-up questions", systemImage: "bubble.left.and.text.bubble.right")
                        .font(.subheadline.weight(.semibold))
                }
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

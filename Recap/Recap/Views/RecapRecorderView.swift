import SwiftData
import SwiftUI

/// Record your end-of-day recap by voice, review the text, then summarize and save.
///
/// Folded, it's one column: transcript on top, controls below. Unfolded, prompts and
/// controls sit on the left and the live transcript fills the right. The recording keeps
/// going while you switch between the two.
struct RecapRecorderView: View {
    @Environment(RecapRecorder.self) private var recorder
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Goal> { !$0.isArchived }, sort: \Goal.createdAt) private var goals: [Goal]
    @Query private var allEntries: [DayEntry]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isSaving = false
    @State private var savedEntry: DayEntry?
    @State private var saveProblem: String?
    @State private var confirmDiscard = false

    /// Regular width (the unfolded Duo) gets prompts beside the transcript.
    private var isWide: Bool { horizontalSizeClass == .regular }

    var body: some View {
        NavigationStack {
            Group {
                if let savedEntry {
                    savedView(savedEntry)
                } else if isWide {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 24) {
                            promptsPanel
                            Spacer(minLength: 0)
                            controls
                        }
                        .frame(maxWidth: 340)
                        transcriptPanel
                    }
                    .padding(24)
                } else {
                    VStack(spacing: 16) {
                        if recorder.phase == .ready && !recorder.hasContent {
                            ScrollView { promptsPanel }
                        } else {
                            transcriptPanel
                        }
                        controls
                    }
                    .padding()
                }
            }
            .navigationTitle(savedEntry == nil ? "Today's Recap" : "Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .interactiveDismissDisabled(savedEntry == nil && (recorder.hasContent || recorder.phase == .recording || isSaving))
        .confirmationDialog("Discard this recap?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { close() }
            Button("Keep recording", role: .cancel) {}
        } message: {
            Text("What you've said so far will be lost.")
        }
        .alert("Microphone", isPresented: .init(
            get: { recorder.errorMessage != nil },
            set: { if !$0 { recorder.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recorder.errorMessage ?? "")
        }
    }

    // MARK: - Pieces

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if savedEntry == nil {
                Button("Cancel") {
                    if recorder.hasContent || recorder.phase == .recording {
                        confirmDiscard = true
                    } else {
                        close()
                    }
                }
                .disabled(isSaving)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if savedEntry != nil {
                Button("Done") { close() }
            }
        }
    }

    private var promptsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Talk through your day")
                .font(.title2.bold())
            Text("No need to be polished. Just say what happened. Some ideas:")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                PromptRow(icon: "hammer", text: "What did you work on today?")
                PromptRow(icon: "trophy", text: "Any wins, big or small?")
                PromptRow(icon: "mountain.2", text: "What was hard, and how did you handle it?")
                PromptRow(icon: "person.2", text: "Who did you work with or help?")
                PromptRow(icon: "number", text: "Any numbers? Time saved, users, dollars, deadlines.")
            }
            // A rotating nudge toward competencies you don't have strong examples of yet.
            if let nudge = CompetencyNudge.today(entries: allEntries) {
                Label(nudge, systemImage: "star.square.on.square")
                    .font(.subheadline.weight(.medium))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if !goals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Did you move any goals forward?")
                        .font(.subheadline.weight(.semibold))
                    FlowLayout {
                        ForEach(goals) { Chip(text: $0.title) }
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transcriptPanel: some View {
        @Bindable var recorder = recorder
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(recorder.phase == .review ? "Your recap. Fix anything that's wrong." : "Live transcript")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if recorder.phase == .recording {
                    Label("Listening", systemImage: "waveform")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                }
            }
            Group {
                if recorder.phase == .review {
                    TextEditor(text: $recorder.transcript)
                        .scrollContentBackground(.hidden)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(recorder.transcript.isEmpty ? "Start talking…" : recorder.transcript)
                                .foregroundStyle(recorder.transcript.isEmpty ? .tertiary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear.frame(height: 1).id("end")
                        }
                        .onChange(of: recorder.transcript) {
                            proxy.scrollTo("end", anchor: .bottom)
                        }
                    }
                }
            }
            .font(.body)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 14) {
            switch recorder.phase {
            case .ready:
                RecordButton(isRecording: false) { Task { await recorder.start() } }
                Text("Tap to start").font(.subheadline).foregroundStyle(.secondary)
            case .recording:
                Text(Self.format(recorder.elapsed))
                    .font(.title3.monospacedDigit().weight(.semibold))
                RecordButton(isRecording: true) { Task { await recorder.stop() } }
                Text("Tap when you're done").font(.subheadline).foregroundStyle(.secondary)
            case .finishing:
                ProgressView("Catching your last words…")
            case .review:
                if isSaving {
                    ProgressView("Summarizing your day…")
                        .padding(.vertical)
                } else {
                    Button {
                        Task { await save() }
                    } label: {
                        Label("Summarize & Save", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!recorder.hasContent)

                    Button {
                        Task { await recorder.start(appending: true) }
                    } label: {
                        Label("Add more", systemImage: "mic")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func savedView(_ entry: DayEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Saved to your journal", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                if let saveProblem {
                    Text("Your recap is saved, but it couldn't be summarized yet: \(saveProblem) You can try again from the journal.")
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                Text(entry.displayTitle).font(.title.bold())
                EntrySummaryContent(entry: entry)
            }
            .padding()
            .readableWidth()
        }
    }

    // MARK: - Actions

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        // Save what you said first, so nothing is lost if the summary fails.
        let entry = DayEntry(transcript: recorder.transcript.trimmed)
        context.insert(entry)
        try? context.save()

        do {
            try await RecapProcessor.summarize(entry, goals: goals)
            try? context.save()
        } catch {
            saveProblem = error.localizedDescription
        }
        savedEntry = entry
    }

    private func close() {
        recorder.reset()
        savedEntry = nil
        saveProblem = nil
        dismiss()
    }

    private static func format(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct PromptRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon).foregroundStyle(Color.accentColor)
        }
    }
}

private struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.accentColor)
                    .frame(width: 84, height: 84)
                    .shadow(color: (isRecording ? Color.red : Color.accentColor).opacity(0.35), radius: 12)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .sensoryFeedback(.impact, trigger: isRecording)
    }
}

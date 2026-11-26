import AVFoundation
import Foundation
import Observation
import Speech

/// Records your voice and turns it into text live, on your device.
///
/// It lives at the app level (see `RecapApp`), so folding or unfolding the
/// iPhone Duo mid-sentence doesn't stop the recording or lose the transcript.
@MainActor
@Observable
final class RecapRecorder {
    enum Phase: Equatable {
        case ready      // nothing recorded yet
        case recording  // listening
        case finishing  // catching the last few words
        case review     // done talking; transcript can be edited, then summarized
    }

    private(set) var phase: Phase = .ready
    /// The full transcript so far. Editable during review.
    var transcript = ""
    private(set) var elapsed: TimeInterval = 0
    var errorMessage: String?

    // Created the first time you tap a mic, not when a screen is built. SwiftUI builds
    // screens often (for example when the Duo unfolds), and setting these up each time
    // slowed things down.
    @ObservationIgnored private var createdEngine: AVAudioEngine?
    @ObservationIgnored private let box = RequestBox()
    @ObservationIgnored private lazy var recognizer: SFSpeechRecognizer? =
        SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private var engine: AVAudioEngine {
        if let createdEngine { return createdEngine }
        let engine = AVAudioEngine()
        createdEngine = engine
        return engine
    }
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    /// Text from finished speech segments. Recognition runs in segments that
    /// restart automatically, so long recaps and pauses work.
    @ObservationIgnored private var committed = ""
    @ObservationIgnored private var segmentText = ""
    @ObservationIgnored private var segmentID = 0
    @ObservationIgnored private var silentFailures = 0
    @ObservationIgnored private var startDate: Date?
    @ObservationIgnored private var elapsedBeforeStart: TimeInterval = 0
    @ObservationIgnored private var timer: Timer?
    /// True while the microphone is being switched on, so a double-tap can't start twice.
    @ObservationIgnored private var isStarting = false

    var hasContent: Bool { !transcript.trimmed.isEmpty }

    /// Starts listening. With `appending`, new speech is added after the existing transcript.
    func start(appending: Bool = false) async {
        guard phase == .ready || phase == .review, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        errorMessage = nil

        guard await Self.requestPermissions() else {
            errorMessage = "Recap needs microphone and speech recognition access. You can turn them on in the Settings app under Recap."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now. Try again in a moment."
            return
        }

        if appending {
            committed = transcript.trimmed
            elapsedBeforeStart = elapsed
        } else {
            committed = ""
            transcript = ""
            elapsed = 0
            elapsedBeforeStart = 0
        }
        segmentText = ""
        silentFailures = 0

        do {
            // Switching the audio system into recording mode can take a moment, so it
            // happens off the main thread to keep the screen responsive.
            try await AudioSessionController.activate()

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTapBlock(box))
            engine.prepare()
            try engine.start()
        } catch {
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            teardownAudio()
            return
        }

        phase = .recording
        beginSegment(with: recognizer)
        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Stops listening and waits briefly for the last words to come through.
    func stop() async {
        guard phase == .recording else { return }
        phase = .finishing
        tick()
        timer?.invalidate()
        timer = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        box.endAudio()

        try? await Task.sleep(for: .seconds(1.5))
        finishIfNeeded()
    }

    /// Throws everything away and goes back to the start.
    func reset() {
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
        box.set(nil)
        segmentID += 1
        teardownAudio()
        committed = ""
        segmentText = ""
        transcript = ""
        elapsed = 0
        elapsedBeforeStart = 0
        errorMessage = nil
        phase = .ready
    }

    // MARK: - Speech segments

    private func beginSegment(with recognizer: SFSpeechRecognizer) {
        segmentID += 1
        segmentText = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        box.set(request)
        task = recognizer.recognitionTask(
            with: request,
            resultHandler: Self.makeResultHandler(segment: segmentID, owner: self)
        )
    }

    fileprivate func handle(segment: Int, text: String?, isFinal: Bool, failed: Bool) {
        guard segment == segmentID else { return }

        if let text {
            segmentText = text
            transcript = Self.join(committed, text)
            if !text.trimmed.isEmpty { silentFailures = 0 }
        }
        guard isFinal || failed else { return }

        // This segment ended (a long pause, a time limit, or the end of audio).
        let segmentWasEmpty = segmentText.trimmed.isEmpty
        committed = Self.join(committed, segmentText)
        segmentText = ""
        transcript = committed

        switch phase {
        case .recording:
            if failed && segmentWasEmpty { silentFailures += 1 }
            if silentFailures > 12 {
                errorMessage = "Listening stopped after a long silence. Everything you said is saved below."
                Task { await stop() }
                return
            }
            if let recognizer { beginSegment(with: recognizer) }
        case .finishing:
            finishIfNeeded()
        case .ready, .review:
            break
        }
    }

    private func finishIfNeeded() {
        guard phase == .finishing else { return }
        task?.cancel()
        task = nil
        box.set(nil)
        segmentID += 1
        committed = Self.join(committed, segmentText)
        segmentText = ""
        transcript = committed
        AudioSessionController.deactivate()
        phase = .review
    }

    private func tick() {
        guard let startDate, phase == .recording || phase == .finishing else { return }
        elapsed = elapsedBeforeStart + Date().timeIntervalSince(startDate)
    }

    private func teardownAudio() {
        if let engine = createdEngine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        AudioSessionController.deactivate()
    }

    private static func join(_ a: String, _ b: String) -> String {
        let a = a.trimmed, b = b.trimmed
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }

    // MARK: - Callbacks that run off the main thread
    //
    // These are built in nonisolated functions on purpose: the audio tap and the
    // speech callbacks run on background threads, and they hop back to the main
    // actor explicitly.

    nonisolated private static func makeTapBlock(_ box: RequestBox) -> AVAudioNodeTapBlock {
        { buffer, _ in box.append(buffer) }
    }

    nonisolated private static func makeResultHandler(
        segment: Int,
        owner: RecapRecorder
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak owner] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                owner?.handle(segment: segment, text: text, isFinal: isFinal, failed: failed)
            }
        }
    }

    nonisolated private static func requestPermissions() async -> Bool {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}

/// Lets the audio thread hand microphone buffers to the current speech request safely.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ newValue: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request = newValue
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = request
        lock.unlock()
        current?.append(buffer)
    }

    func endAudio() {
        lock.lock()
        let current = request
        lock.unlock()
        current?.endAudio()
    }
}

/// Turns the shared audio session on and off on a background queue.
///
/// iOS warns that activating or deactivating the session on the main thread can make the
/// app unresponsive. A single serial queue also keeps the order right: if you stop and
/// immediately start again ("Add more"), the "off" always finishes before the next "on".
enum AudioSessionController {
    private static let queue = DispatchQueue(label: "recap.audio-session", qos: .userInitiated)

    static func activate() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.record, mode: .measurement, options: .duckOthers)
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func deactivate() {
        queue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

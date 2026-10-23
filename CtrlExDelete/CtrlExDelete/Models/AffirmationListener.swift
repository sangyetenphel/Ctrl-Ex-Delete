import AVFoundation
import Speech

/// Who is using the microphone. Only one at a time: the plant game can't
/// record during a Ced voice call, and a call can't start while the game
/// records. (The app has no voice call yet; when one is added it must
/// `acquire(.cedVoiceCall)` here too.)
@MainActor
final class MicrophoneCoordinator {
    enum Owner { case affirmationGame, cedVoiceCall }

    static let shared = MicrophoneCoordinator()
    private(set) var owner: Owner?

    /// True if `owner` now has the microphone (or already had it).
    func acquire(_ owner: Owner) -> Bool {
        if self.owner == nil || self.owner == owner {
            self.owner = owner
            return true
        }
        return false
    }

    func release(_ owner: Owner) {
        if self.owner == owner { self.owner = nil }
    }
}

/// Listens while the user reads an affirmation aloud, using Apple's Speech
/// framework (on-device when the phone supports it for the language), and
/// reports how many of the sentence's words have been heard, in order.
///
/// Nothing is recorded or saved: audio goes straight to the recognizer and
/// the transcript is only used to colour the words on screen.
@Observable
@MainActor
final class AffirmationListener {
    enum State: Equatable {
        case idle
        case preparing                 // asking for permission, starting up
        case listening
        case processing                // stopped, waiting for the last result
        case retry(String)             // gentle: try again or "I said it"
        case unavailable(String)       // no permission or no recognizer: practice quietly
    }

    private(set) var state = State.idle
    /// Matched tokens of the current sentence (including earlier attempts).
    private(set) var matched = 0

    /// Called once when every word has been heard.
    var onComplete: (() -> Void)?

    private var matcher: AffirmationMatcher?
    /// Tokens matched before this listening attempt (kept across retries).
    private var carried = 0
    private var hasCompleted = false

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var silenceTimer: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?
    /// Ignores late callbacks from an attempt that has already ended.
    private var attempt = 0

    /// Seconds without a new word before listening stops gently.
    private let quietLimit: Duration = .seconds(7)

    // MARK: The sentence

    /// A new sentence (or "Try another"): stops listening and starts fresh.
    func prepare(for sentence: String) {
        stop()
        matcher = AffirmationMatcher(sentence: sentence)
        matched = 0
        carried = 0
        hasCompleted = false
        if case .retry = state { state = .idle }
        if state == .processing { state = .idle }
    }

    var greenWords: Set<Int> { matcher?.greenWords(matched: matched) ?? [] }
    var displayWords: [String] { matcher?.displayWords ?? [] }

    // MARK: Start and stop

    /// The microphone button: starts listening, or stops it.
    func toggle() async {
        switch state {
        case .listening: finishListening()
        case .preparing: stop(nextState: .idle)
        case .processing: break
        default: await start()
        }
    }

    /// The user tapped to stop: the microphone stops now, and the last words
    /// are given a moment to arrive (they may still complete the sentence).
    private func finishListening() {
        silenceTimer?.cancel()
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        state = .processing
        let thisAttempt = attempt
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, self.attempt == thisAttempt, self.state == .processing else { return }
            self.stop(nextState: .idle)
        }
    }

    func start() async {
        guard matcher != nil, !hasCompleted, state != .listening, state != .preparing else { return }
        state = .preparing

        guard await Self.requestPermissions() else {
            state = .unavailable("Microphone or speech recognition is turned off for Ctrl+Ex+Delete. You can practice quietly, or turn them on in Settings.")
            return
        }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable("Speech recognition isn\u{2019}t available right now. You can practice quietly instead.")
            return
        }
        guard MicrophoneCoordinator.shared.acquire(.affirmationGame) else {
            state = .retry("The microphone is busy with a call. Try again once it ends.")
            return
        }
        guard state == .preparing else {          // stopped while permissions were asked
            MicrophoneCoordinator.shared.release(.affirmationGame)
            return
        }

        do {
            try beginRecognition(with: recognizer)
            state = .listening
            restartSilenceTimer()
        } catch {
            stop(nextState: .retry("The microphone couldn\u{2019}t start. Please try again."))
        }
    }

    /// Stops listening and releases the microphone. Safe to call any time.
    func stop(nextState: State? = nil) {
        attempt += 1
        silenceTimer?.cancel()
        silenceTimer = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        MicrophoneCoordinator.shared.release(.affirmationGame)
        carried = matched                         // a later attempt continues from here
        if let nextState {
            state = nextState
        } else if state == .listening || state == .preparing || state == .processing {
            state = .idle
        }
    }

    /// For "I said it" / "I'm ready": the sentence counts, without pretending it was recognised.
    func markCompletedManually() {
        stop(nextState: .idle)
        hasCompleted = true
    }

    // MARK: Recognition

    private func beginRecognition(with recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        // On-device when the phone supports it for English; otherwise Apple's
        // servers do the recognition (nothing is kept by Ctrl+Ex+Delete).
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.contextualStrings = displayWords
        self.request = request
        self.recognizer = recognizer

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        attempt += 1
        let thisAttempt = attempt
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                self?.handle(transcript: transcript, isFinal: isFinal, failed: failed, attempt: thisAttempt)
            }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // A call or alarm took the audio: stop; another tap resumes.
                self?.stop(nextState: .retry("Listening paused. Tap the microphone when you\u{2019}re ready."))
            }
        }
    }

    private func handle(transcript: String?, isFinal: Bool, failed: Bool, attempt thisAttempt: Int) {
        guard thisAttempt == attempt, !hasCompleted, let matcher else { return }
        if let transcript {
            // Recomputed from the whole (possibly revised) transcript every
            // time, so repeated or revised callbacks never double-count.
            let count = matcher.matchedCount(in: transcript, from: carried)
            if count != matched { restartSilenceTimer() }
            matched = max(count, carried)
            if matched >= matcher.tokenCount {
                hasCompleted = true
                stop(nextState: .idle)
                onComplete?()                     // exactly once per sentence
                return
            }
        }
        if state == .processing, failed || isFinal {
            stop(nextState: .idle)                 // the user stopped; they can carry on later
        } else if failed || isFinal {
            stop(nextState: .retry("I didn\u{2019}t catch all of it. Take your time and try again."))
        }
    }

    private func restartSilenceTimer() {
        silenceTimer?.cancel()
        let thisAttempt = attempt
        silenceTimer = Task { [weak self, quietLimit] in
            try? await Task.sleep(for: quietLimit)
            guard !Task.isCancelled, let self, self.attempt == thisAttempt, self.state == .listening else { return }
            self.stop(nextState: .retry("It got quiet, so I stopped listening. Try again whenever you like."))
        }
    }

    // MARK: Permissions

    /// Asks the first time the microphone is tapped; afterwards just checks.
    private static func requestPermissions() async -> Bool {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            } else {
                continuation.resume(returning: SFSpeechRecognizer.authorizationStatus())
            }
        }
        guard speech == .authorized else { return false }
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }
}

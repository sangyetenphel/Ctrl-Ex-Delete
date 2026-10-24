import AVFoundation
import Foundation

/// What happens on a call, from the server (or the mock).
nonisolated enum VoiceEvent: Sendable {
    case ready
    case activity(String)                 // "listening", "thinking", "speaking"
    case audio(Data)                      // Ced's voice, PCM 16-bit, 24 kHz, mono
    case interrupted                      // the user talked over Ced
    case safety(CrisisSupport)
    case ended(reason: String)
    case failed(code: String, message: String)
}

/// The connection behind a call: the real one (backend + Gemini Live) or the mock.
/// Called from audio and network threads, so it isn't tied to the main actor.
nonisolated protocol VoiceTransport: AnyObject, Sendable {
    /// Whether this is the practice mock (shown on the call screen).
    var isMock: Bool { get }
    func connect(onEvent: @escaping @Sendable (VoiceEvent) -> Void)
    func sendAudio(_ pcm: Data, level: Float)
    func setMuted(_ muted: Bool)
    func close()
}

// MARK: - Real calls (WebSocket to the backend)

/// Streams audio to `ws(s)://<API>/ced/voice`. The backend holds the Gemini
/// key and relays to Gemini Live; the app never sees any credential.
/// Message format: backend/app/ced/voice.py.
nonisolated final class LiveVoiceTransport: VoiceTransport, @unchecked Sendable {
    let isMock = false
    private let request: URLRequest
    private let setupFailure: String?     // why the call can't connect at all
    private var task: URLSessionWebSocketTask?
    private var onEvent: (@Sendable (VoiceEvent) -> Void)?
    private var closed = false
    private let lock = NSLock()

    /// `baseURL`: the API (http or https); the call uses ws or wss on the same host.
    /// `installationID`: a failure (the Keychain couldn't be read yet) makes the
    /// call end with its message instead of connecting under another ID.
    init(baseURL: URL, installationID: Result<UUID, any Error>) {
        var components = URLComponents(url: baseURL.appending(path: "ced/voice"), resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        var request = URLRequest(url: components.url!)
        switch installationID {
        case .success(let id):
            request.setValue(id.uuidString, forHTTPHeaderField: "X-Installation-ID")
            setupFailure = nil
        case .failure(let error):
            setupFailure = error.localizedDescription
        }
        request.timeoutInterval = 60     // the deployed server may be waking up
        self.request = request
    }

    func connect(onEvent: @escaping @Sendable (VoiceEvent) -> Void) {
        self.onEvent = onEvent
        if let setupFailure {
            lock.withLock { closed = true }
            onEvent(.failed(code: "installation", message: setupFailure))
            return
        }
        CallDiagnostics.log("websocket connecting to \(request.url?.host() ?? "?"):\(request.url?.port ?? 0)\(request.url?.path() ?? "")")
        let task = URLSession.shared.webSocketTask(with: request)
        task.maximumMessageSize = 4 * 1024 * 1024
        self.task = task
        task.resume()
        receive()
        keepAlive()
    }

    /// Pings the server every 10 s; a failed ping means the connection is
    /// dead (e.g. Wi-Fi dropped) even though no error arrived.
    private func keepAlive() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, !self.isClosed, let task = self.task else { return }
            task.sendPing { error in
                guard !self.isClosed else { return }
                if let error {
                    CallDiagnostics.log("keep-alive ping failed: \((error as NSError).domain) \((error as NSError).code)")
                    self.lock.withLock { self.closed = true }
                    self.onEvent?(.failed(code: "dropped",
                                          message: "The call with Ced dropped. Tap \u{201C}Call again\u{201D} to reconnect."))
                } else {
                    self.keepAlive()
                }
            }
        }
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.data(let data)):
                self.onEvent?(.audio(data))
                self.receive()
            case .success(.string(let text)):
                CallDiagnostics.log("server event: \(Self.eventSummary(text))")
                if let event = Self.event(from: text) {
                    // After an error the server hangs up; that isn't a second problem.
                    if case .failed = event { self.lock.withLock { self.closed = true } }
                    self.onEvent?(event)
                }
                self.receive()
            case .success:
                self.receive()
            case .failure(let error):
                CallDiagnostics.log("websocket receive ended: \((error as NSError).domain) \((error as NSError).code), closed by app \(self.isClosed)")
                if !self.isClosed {
                    self.onEvent?(.failed(code: "dropped",
                                          message: "The call with Ced dropped. Tap \u{201C}Call again\u{201D} to reconnect."))
                }
            }
        }
    }

    private static func event(from text: String) -> VoiceEvent? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return nil }
        switch type {
        case "ready": return .ready
        case "state": return (json["state"] as? String).map(VoiceEvent.activity)
        case "interrupted": return .interrupted
        case "safety": return (json["support"] as? String).flatMap(CrisisSupport.init(rawValue:)).map(VoiceEvent.safety)
        case "ended": return .ended(reason: json["reason"] as? String ?? "")
        case "error":
            return .failed(code: json["code"] as? String ?? "dropped",
                           message: json["message"] as? String ?? "The call dropped. Please try calling again.")
        default: return nil
        }
    }

    private var sentChunks = 0
    private var sentBytes = 0

    func sendAudio(_ pcm: Data, level: Float) {
        guard !isClosed else { return }
        sentChunks += 1
        sentBytes += pcm.count
        if sentChunks == 1 || sentChunks % 100 == 0 {
            CallDiagnostics.log("mic audio sent to server: \(sentChunks) chunks / \(sentBytes) B")
        }
        task?.send(.data(pcm)) { error in
            if let error { CallDiagnostics.log("websocket send failed: \((error as NSError).code)") }
        }
    }

    /// Type and state only, never content.
    private static func eventSummary(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "unreadable" }
        let type = json["type"] as? String ?? "?"
        let detail = (json["state"] ?? json["code"] ?? json["support"] ?? json["reason"]) as? String
        return detail.map { "\(type) \($0)" } ?? type
    }

    func setMuted(_ muted: Bool) {
        task?.send(.string(muted ? #"{"type":"mute"}"# : #"{"type":"unmute"}"#)) { _ in }
    }

    func close() {
        lock.withLock { closed = true }
        task?.send(.string(#"{"type":"end"}"#)) { [task] _ in task?.cancel(with: .normalClosure, reason: nil) }
    }

    private var isClosed: Bool { lock.withLock { closed } }
}

#if DEBUG
// MARK: - Practice mock (Debug builds only)

/// MOCK VOICE — for building and testing the call screen without a Gemini key.
/// Ced's lines are canned and spoken with the system's speech synthesizer;
/// "hearing" the user is just microphone loudness. Nothing leaves the device.
/// The call screen labels it clearly as practice mode.
nonisolated final class MockVoiceTransport: VoiceTransport, @unchecked Sendable {
    let isMock = true
    /// Launch argument `-CEDMockVoiceCrisis YES`: pretend a crisis was detected
    /// after the greeting, to test the on-call support panel.
    private let simulateCrisis = UserDefaults.standard.bool(forKey: "CEDMockVoiceCrisis")

    private let synthesizer = AVSpeechSynthesizer()
    private let queue = DispatchQueue(label: "ced.mock-voice")
    private var onEvent: (@Sendable (VoiceEvent) -> Void)?
    private var speaking = false
    private var muted = false
    private var heardSpeechSince: Date?
    private var lastSpeechAt: Date?
    private var replyIndex = 0
    private var loudWhileSpeakingSince: Date?
    private var closed = false

    private let greeting = "Hi, it\u{2019}s Ced. I\u{2019}m really glad you called. How are you doing right now?"
    private let replies = [
        "That sounds like a lot to carry. I\u{2019}m here, so take your time.",
        "Thank you for telling me. What feels hardest about it tonight?",
        "I hear you. Is there one small, kind thing you could do for yourself right now?",
    ]

    func connect(onEvent: @escaping @Sendable (VoiceEvent) -> Void) {
        self.onEvent = onEvent
        queue.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, !self.closed else { return }
            onEvent(.ready)
            self.speak(self.greeting) {}
            if self.simulateCrisis {
                self.queue.asyncAfter(deadline: .now() + 3) { if !self.closed { onEvent(.safety(.crisis)) } }
            }
        }
    }

    func sendAudio(_ pcm: Data, level: Float) {
        queue.async { [weak self] in self?.listen(level: level) }
    }

    func setMuted(_ muted: Bool) {
        queue.async { [weak self] in self?.muted = muted }
    }

    func close() {
        queue.async { [weak self] in
            self?.closed = true
            self?.synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// Very rough turn-taking: loud for a moment = talking; quiet for a
    /// second after that = their turn is over.
    private func listen(level: Float) {
        guard !closed, !muted else { return }
        let now = Date()
        if level > 0.12 {
            if speaking {
                // Talking over Ced for a moment (not just a click) interrupts her.
                let since = loudWhileSpeakingSince ?? now
                loudWhileSpeakingSince = since
                guard now.timeIntervalSince(since) > 0.35 else { return }
                loudWhileSpeakingSince = nil
                synthesizer.stopSpeaking(at: .immediate)
                speaking = false
                onEvent?(.interrupted)
                onEvent?(.activity("listening"))
            }
            if heardSpeechSince == nil { heardSpeechSince = now }
            lastSpeechAt = now
        } else if speaking {
            loudWhileSpeakingSince = nil
        } else if let since = heardSpeechSince, let last = lastSpeechAt,
                  last.timeIntervalSince(since) > 0.4, now.timeIntervalSince(last) > 1.0 {
            heardSpeechSince = nil
            lastSpeechAt = nil
            onEvent?(.activity("thinking"))
            queue.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, !self.closed else { return }
                let line = self.replies[self.replyIndex % self.replies.count]
                self.replyIndex += 1
                self.speak(line) {}
            }
        }
    }

    /// Speaks through the same playback path as a real call.
    private func speak(_ text: String, then: @escaping @Sendable () -> Void) {
        speaking = true
        onEvent?(.activity("speaking"))
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.47
        let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: CallAudio.playbackRate,
                                   channels: 1, interleaved: true)!
        var converter: AVAudioConverter?
        let started = Date()
        var framesSent = 0
        synthesizer.write(utterance) { [weak self] buffer in
            guard let self, !self.closed, let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 {
                // All audio is written; it finishes playing a bit later.
                let remaining = max(0, Double(framesSent) / CallAudio.playbackRate - Date().timeIntervalSince(started))
                self.queue.asyncAfter(deadline: .now() + remaining) {
                    guard self.speaking else { return }
                    self.speaking = false
                    self.onEvent?(.activity("listening"))
                    then()
                }
                return
            }
            guard self.speaking else { return }
            if converter == nil { converter = AVAudioConverter(from: pcm.format, to: target) }
            let capacity = AVAudioFrameCount(Double(pcm.frameLength) * target.sampleRate / pcm.format.sampleRate) + 32
            guard let converter, let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var fed = false
            converter.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return pcm
            }
            guard out.frameLength > 0, let samples = out.int16ChannelData?[0] else { return }
            framesSent += Int(out.frameLength)
            self.onEvent?(.audio(Data(bytes: samples, count: Int(out.frameLength) * 2)))
        }
    }
}
#endif

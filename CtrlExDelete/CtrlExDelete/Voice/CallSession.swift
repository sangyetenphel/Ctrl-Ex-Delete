import AVFoundation
import SwiftUI

/// One voice call with Ced, from "Calling Ced…" to hanging up.
@Observable
final class CallSession {
    enum Phase: Equatable {
        case connecting
        case active
        case ended(String)       // why, shown with a "Close" button
    }

    enum Activity: String {
        case listening, thinking, speaking, reconnecting

        var label: String {
            switch self {
            case .listening: "Listening\u{2026}"
            case .thinking: "Ced is thinking\u{2026}"
            case .speaking: "Ced is speaking\u{2026}"
            case .reconnecting: "Reconnecting\u{2026}"
            }
        }
    }

    /// The server normally moves on within seconds; this long with no word at
    /// all while waiting on Ced means the call is stuck.
    private static let silentServerTimeout: TimeInterval = 25

    private(set) var phase = Phase.connecting
    private(set) var activity = Activity.listening
    private(set) var isMuted = false
    private(set) var isSpeakerOn = true
    private(set) var connectedAt: Date?
    /// Crisis resources showing on the call screen (never opened automatically);
    /// nil while hidden.
    private(set) var support: CrisisSupport?
    /// The most urgent resources the server asked for during this call, kept
    /// after "Hide" and after the call ends, so they're always one tap away.
    private(set) var flaggedSupport: CrisisSupport?
    /// The panel also lists the National Domestic Violence Hotline.
    private(set) var showsDVHotline = false
    private(set) var isMock = false
    /// 0…1, for the avatar: Ced's voice while speaking, the mic while listening.
    private(set) var level: Float = 0

    private let audio = CallAudio()
    private var transport: VoiceTransport
    private var interruptionObserver: NSObjectProtocol?
    private let lastServerEvent = ServerClock()
    private var watchdog: Task<Void, Never>?

    init() {
        #if DEBUG
        transport = UserDefaults.standard.bool(forKey: "CEDMockVoice") ? MockVoiceTransport() : Self.liveTransport()
        #else
        transport = Self.liveTransport()
        #endif
    }

    private static func liveTransport() -> VoiceTransport {
        LiveVoiceTransport(baseURL: APIConfig.baseURL, installationID: Result { try InstallationID.current() })
    }

    // MARK: Calling

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            phase = .ended("Ced needs the microphone for calls. You can allow it in Settings \u{203A} Ctrl+Ex+Delete.")
            return
        }
        let call = WeakCall(self)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            guard type == .began else { return }
            MainActor.assumeIsolated { call.session?.finish("The call was interrupted.") }
        }
        connect()
    }

    private func connect() {
        isMock = transport.isMock
        CallDiagnostics.log("call starting with \(transport.isMock ? "MOCK voice (Debug practice mode)" : "LIVE voice (backend + Gemini)")")
        let audio = self.audio
        let call = WeakCall(self)
        let source = ObjectIdentifier(transport)
        let clock = lastServerEvent
        clock.touch()
        transport.connect { event in
            clock.touch()
            // Ced's voice goes straight to the speaker; everything else to the UI.
            if case .audio(let pcm) = event {
                audio.play(pcm)
                return
            }
            Task { @MainActor in call.session?.handle(event, from: source) }
        }
    }

    private func handle(_ event: VoiceEvent, from source: ObjectIdentifier) {
        // Ignore late events from a connection that was already replaced
        // (e.g. the server closing after saying voice isn't available).
        guard source == ObjectIdentifier(transport) else {
            CallDiagnostics.log("ignored event from a replaced connection")
            return
        }
        switch event {
        case .ready:
            guard phase == .connecting else { return }
            startAudio()
        case .activity(let name):
            activity = Activity(rawValue: name) ?? .listening
            if activity != .speaking { level = 0 }
        case .interrupted:
            audio.stopPlayback()
            activity = .listening
        case .safety(let kind, let dvHotline):
            // The more urgent panel wins (danger shows 911 first). Something
            // new brings it back even if it was hidden.
            if flaggedSupport != .danger { flaggedSupport = kind }
            showsDVHotline = showsDVHotline || dvHotline
            support = flaggedSupport
        case .ended(let reason):
            finish(reason == "time_limit" ? "Calls can last up to 15 minutes. You can call Ced again anytime." : "Call ended.")
        case .failed(let code, let message):
            #if DEBUG
            // No Gemini key on the server yet: practise with the mock instead.
            if code == "unavailable", phase == .connecting, !transport.isMock {
                transport.close()
                transport = MockVoiceTransport()
                connect()
                return
            }
            #endif
            finish(message)
        case .audio:
            break
        }
    }

    private func startAudio() {
        let transport = self.transport
        let call = WeakCall(self)
        audio.onCapture = { pcm, level in
            transport.sendAudio(pcm, level: level)
            Task { @MainActor in call.session?.micLevel(level) }
        }
        audio.onPlaybackLevel = { level in
            Task { @MainActor in call.session?.level = level }
        }
        do {
            try audio.start(speakerOn: isSpeakerOn)
        } catch {
            finish("Your microphone couldn\u{2019}t be started. Please try again.")
            return
        }
        phase = .active
        connectedAt = .now
        startWatchdog()
        CallDiagnostics.log("call active")
    }

    private func micLevel(_ value: Float) {
        guard activity == .listening, !isMuted else { return }
        level = value
    }

    // MARK: Controls

    func toggleMute() {
        isMuted.toggle()
        transport.setMuted(isMuted)
        if isMuted { level = 0 }
    }

    func toggleSpeaker() {
        isSpeakerOn.toggle()
        audio.setSpeaker(isSpeakerOn)
    }

    /// Hangs up. Safe to call more than once.
    func end() {
        finish("Call ended.")
    }

    /// Shows the support panel on request (the user tapped "Support"): what
    /// this call flagged, or 988 by default.
    func showSupport() {
        if support == nil { support = flaggedSupport ?? .crisis }
    }

    func hideSupport() {
        support = nil
    }

    /// Ends a call that's stuck waiting on Ced with no word from the server.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.phase == .active else { return }
                let waitingOnCed = self.activity != .listening
                if waitingOnCed, self.lastServerEvent.secondsSince > Self.silentServerTimeout {
                    CallDiagnostics.log("watchdog: no server events for \(Int(Self.silentServerTimeout)) s while \(self.activity.rawValue)")
                    self.finish("Ced stopped responding. Tap \u{201C}Call again\u{201D} to reconnect.")
                    return
                }
            }
        }
    }

    private func finish(_ reason: String) {
        if case .ended = phase { return }
        CallDiagnostics.log("call finished")
        watchdog?.cancel()
        phase = .ended(reason)
        // Resources flagged during the call stay on the screen after it ends
        // (hung up, dropped or timed out): that's when they matter most.
        if let flaggedSupport { support = flaggedSupport }
        transport.close()
        audio.onCapture = nil
        audio.stop()
        level = 0
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
    }
}

/// A weak reference that audio and network callbacks can hold safely.
private final class WeakCall: Sendable {
    nonisolated(unsafe) weak var session: CallSession?
    nonisolated init(_ session: CallSession) { self.session = session }
}

/// When the server last sent anything (audio or an event). Thread-safe.
private final class ServerClock: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var last = Date()

    nonisolated func touch() { lock.withLock { last = Date() } }
    nonisolated var secondsSince: TimeInterval { lock.withLock { Date().timeIntervalSince(last) } }
}

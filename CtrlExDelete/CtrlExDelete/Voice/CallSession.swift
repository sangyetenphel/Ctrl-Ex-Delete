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
        case listening, thinking, speaking

        var label: String {
            switch self {
            case .listening: "Listening\u{2026}"
            case .thinking: "Ced is thinking\u{2026}"
            case .speaking: "Ced is speaking\u{2026}"
            }
        }
    }

    private(set) var phase = Phase.connecting
    private(set) var activity = Activity.listening
    private(set) var isMuted = false
    private(set) var isSpeakerOn = true
    private(set) var connectedAt: Date?
    /// Crisis resources to show on the call screen (never opened automatically).
    private(set) var support: CrisisSupport?
    private(set) var isMock = false
    /// 0…1, for the avatar: Ced's voice while speaking, the mic while listening.
    private(set) var level: Float = 0

    private let audio = CallAudio()
    private var transport: VoiceTransport
    private var interruptionObserver: NSObjectProtocol?

    init() {
        #if DEBUG
        transport = UserDefaults.standard.bool(forKey: "CEDMockVoice") ? MockVoiceTransport() : Self.liveTransport()
        #else
        transport = Self.liveTransport()
        #endif
    }

    private static func liveTransport() -> VoiceTransport {
        LiveVoiceTransport(baseURL: APIConfig.baseURL, installationID: InstallationID.current)
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
        let audio = self.audio
        let call = WeakCall(self)
        let source = ObjectIdentifier(transport)
        transport.connect { event in
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
        guard source == ObjectIdentifier(transport) else { return }
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
        case .safety(let kind):
            // The more urgent panel wins (danger shows 911 first).
            if support != .danger { support = kind }
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

    /// Shows the support panel on request (the user tapped "Support").
    func showSupport() {
        if support == nil { support = .crisis }
    }

    func hideSupport() {
        support = nil
    }

    private func finish(_ reason: String) {
        if case .ended = phase { return }
        phase = .ended(reason)
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

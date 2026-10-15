@preconcurrency import AVFoundation

/// Microphone in, Ced's voice out, for a voice call.
///
/// - Capture: the microphone is converted to 16 kHz mono 16-bit PCM (what the
///   backend and Gemini Live expect) and handed to `onCapture` in ~100 ms chunks.
/// - Playback: Ced's 24 kHz 16-bit PCM is queued as it streams in, so speech
///   starts before the whole reply has arrived. `stopPlayback()` drops what's
///   queued when the user interrupts.
/// - Echo cancellation (voice processing) keeps Ced from hearing herself
///   through the speaker, so the user can still talk over her.
///
/// Turning on voice processing or changing the speaker route makes iOS
/// reconfigure the audio hardware, which STOPS the engine and posts
/// `AVAudioEngineConfigurationChange`. When that happens the engine is
/// rebuilt and restarted, and Ced's audio that arrives meanwhile is held
/// and played afterwards instead of being lost.
///
/// Simulator only: the simulator plays Ced through the Mac's speakers and
/// records with the Mac's microphone, and iOS echo cancellation can't remove
/// that, so Gemini would hear Ced and treat it as the user talking over her.
/// There, while Ced's voice is actually playing (tracked by the player's
/// played-back callbacks) and briefly after, the microphone sends silence.
/// Talking over Ced therefore only works on a real iPhone (or with headphones
/// on the Mac, where there is no echo).
///
/// Callbacks run on audio and network threads, so this type isn't tied to
/// the main actor; engine changes happen on one serial queue.
nonisolated final class CallAudio: @unchecked Sendable {
    static let captureRate: Double = 16_000
    static let playbackRate: Double = 24_000
    /// At most this much of Ced's voice is held while the engine (re)starts.
    private static let maxPendingBytes = Int(playbackRate) * 2 * 20  // 20 s

    /// Raw PCM chunk for the server, plus its loudness (0…1).
    var onCapture: (@Sendable (Data, Float) -> Void)?
    /// Loudness (0…1) of Ced's voice as it plays, for the avatar.
    var onPlaybackLevel: (@Sendable (Float) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: playbackRate,
                                               channels: 1, interleaved: false)!
    private let captureFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: captureRate,
                                              channels: 1, interleaved: true)!
    private let queue = DispatchQueue(label: "ced.call-audio")
    private let lock = NSLock()

    // Guarded by `lock`: touched from the audio, network and engine threads.
    private var converter: AVAudioConverter?
    private var isActive = false          // between start() and stop()
    private var isReady = false           // engine and player actually running
    private var pending: [Data] = []      // Ced's audio waiting for the engine
    private var pendingBytes = 0
    private var restarts = 0
    private var configObserver: NSObjectProtocol?
    private var buffersPlaying = 0             // scheduled, not yet played back
    private var lastPlaybackEnd = Date.distantPast
    private var echoGuardedChunks = 0

    #if targetEnvironment(simulator)
    private static let guardsAgainstEcho = true
    #else
    private static let guardsAgainstEcho = false   // the iPhone's echo cancellation handles it
    #endif
    private static let echoTail: TimeInterval = 0.45

    // Diagnostics counters (counts and sizes only).
    private var micChunks = 0
    private var micLevelSum: Float = 0
    private var playChunks = 0
    private var playBytes = 0
    private var heldChunks = 0

    func start(speakerOn: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
        try session.setPreferredSampleRate(48_000)
        try session.setActive(true)
        setSpeaker(speakerOn)

        // Echo cancellation. Not available in every environment, where the
        // call still works without it.
        var voiceProcessing = "on"
        do { try engine.inputNode.setVoiceProcessingEnabled(true) } catch { voiceProcessing = "unavailable (\(error))" }
        CallDiagnostics.log("audio session: category \(session.category.rawValue), mode \(session.mode.rawValue), " +
            "hw rate \(session.sampleRate) Hz, input available \(session.isInputAvailable), voice processing \(voiceProcessing)")
        CallDiagnostics.log("route in: \(session.currentRoute.inputs.map(\.portType.rawValue)) " +
            "out: \(session.currentRoute.outputs.map(\.portType.rawValue)), output volume \(session.outputVolume)")

        engine.attach(player)
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.restartAfterConfigurationChange() }
        }
        lock.withLock { isActive = true }
        try queue.sync { try startEngine(reason: "call started") }
    }

    func stop() {
        CallDiagnostics.log("audio stop: mic chunks \(micChunks) (echo-guarded \(echoGuardedChunks)), " +
            "played \(playChunks) chunks / \(playBytes) B, held while starting \(heldChunks), engine restarts \(restarts)")
        let wasActive = lock.withLock {
            defer { isActive = false; isReady = false; pending = []; pendingBytes = 0 }
            return isActive
        }
        guard wasActive else { return }
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        queue.sync {
            engine.inputNode.removeTap(onBus: 0)
            player.stop()
            engine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Speaker (on) or the phone's earpiece / connected headphones (off).
    func setSpeaker(_ on: Bool) {
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(on ? .speaker : .none)
    }

    // MARK: Engine

    /// (Re)builds the graph for the current hardware format and starts it.
    /// Runs on `queue`.
    private func startEngine(reason: String) throws {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "CallAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input"])
        }
        lock.withLock { converter = AVAudioConverter(from: inputFormat, to: captureFormat) }
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(inputFormat.sampleRate / 10), format: inputFormat) {
            [weak self] buffer, _ in self?.capture(buffer)
        }
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        engine.prepare()
        try engine.start()
        player.play()

        let held = lock.withLock {
            isReady = true
            defer { pending = []; pendingBytes = 0 }
            return pending
        }
        CallDiagnostics.log("engine started (\(reason)): running \(engine.isRunning), player playing \(player.isPlaying), " +
            "mic \(inputFormat.sampleRate) Hz x\(inputFormat.channelCount) -> 16000 Hz x1 int16, " +
            "output \(engine.outputNode.outputFormat(forBus: 0).sampleRate) Hz; playing \(held.count) held chunks")
        held.forEach(schedule)
    }

    /// iOS stopped the engine to reconfigure the hardware: start it again.
    private func restartAfterConfigurationChange() {
        let shouldRestart = lock.withLock {
            guard isActive else { return false }
            isReady = false
            restarts += 1
            return restarts <= 10  // never loop forever
        }
        CallDiagnostics.log("engine configuration changed (running \(engine.isRunning)); restart #\(restarts)")
        guard shouldRestart else { return }
        do {
            try startEngine(reason: "after configuration change")
        } catch {
            CallDiagnostics.log("engine restart failed: \((error as NSError).domain) \((error as NSError).code)")
        }
    }

    // MARK: Ced's voice

    /// Queues one chunk of Ced's voice (16-bit little-endian PCM, 24 kHz, mono).
    func play(_ pcm: Data) {
        let ready = lock.withLock { () -> Bool in
            guard isActive else { return true }  // after hang-up: schedule() ignores it
            if isReady { return true }
            // Engine still (re)starting: keep it for a moment instead of losing it.
            if pendingBytes + pcm.count <= Self.maxPendingBytes {
                pending.append(pcm)
                pendingBytes += pcm.count
                heldChunks += 1
            }
            return false
        }
        if ready { schedule(pcm) }
    }

    private func schedule(_ pcm: Data) {
        guard lock.withLock({ isActive && isReady }) else { return }
        let frames = pcm.count / 2
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        var sumOfSquares: Float = 0
        pcm.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<frames {
                let value = Float(Int16(littleEndian: samples[i])) / Float(Int16.max)
                channel[i] = value
                sumOfSquares += value * value
            }
        }
        lock.withLock { buffersPlaying += 1 }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            self.lock.withLock {
                self.buffersPlaying = max(0, self.buffersPlaying - 1)
                self.lastPlaybackEnd = Date()
            }
        }

        playChunks += 1
        playBytes += pcm.count
        if playChunks == 1 || playChunks % 25 == 0 {
            CallDiagnostics.log("ced audio scheduled: chunk #\(playChunks), \(pcm.count) B, total \(playBytes) B, " +
                "player playing \(player.isPlaying), engine running \(engine.isRunning)")
        }
        onPlaybackLevel?(Self.level(rms: (sumOfSquares / Float(frames)).squareRoot()))
    }

    /// Drops everything still queued (the user started talking over Ced).
    func stopPlayback() {
        lock.withLock { pending = []; pendingBytes = 0 }
        queue.async { [self] in
            guard lock.withLock({ isActive && isReady }) else { return }
            player.stop()
            player.play()
            onPlaybackLevel?(0)
        }
    }

    // MARK: Microphone

    private func capture(_ buffer: AVAudioPCMBuffer) {
        guard let converter = lock.withLock({ converter }), let onCapture else { return }
        let ratio = Self.captureRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0, let samples = output.int16ChannelData?[0] else { return }

        let count = Int(output.frameLength)
        var sumOfSquares: Float = 0
        for i in 0..<count {
            let value = Float(samples[i]) / Float(Int16.max)
            sumOfSquares += value * value
        }
        var data = Data(bytes: samples, count: count * MemoryLayout<Int16>.size)
        var level = Self.level(rms: (sumOfSquares / Float(count)).squareRoot())
        if Self.guardsAgainstEcho, isCedAudible {
            // Same length, all zeros: Gemini hears silence instead of Ced's echo.
            data = Data(count: data.count)
            level = 0
            echoGuardedChunks += 1
            if echoGuardedChunks == 1 || echoGuardedChunks % 50 == 0 {
                CallDiagnostics.log("simulator echo guard: \(echoGuardedChunks) mic chunks silenced while Ced plays")
            }
        }
        micChunks += 1
        micLevelSum += level
        if micChunks == 1 || micChunks % 50 == 0 {
            CallDiagnostics.log("mic chunk #\(micChunks): \(buffer.frameLength) frames @ \(buffer.format.sampleRate) Hz -> " +
                "\(count) samples (\(data.count) B); avg level \(String(format: "%.3f", micLevelSum / Float(micChunks == 1 ? 1 : 50)))")
            micLevelSum = 0
        }
        onCapture(data, level)
    }

    /// Ced's voice is coming out of the speaker now (or just stopped).
    private var isCedAudible: Bool {
        lock.withLock { buffersPlaying > 0 || Date().timeIntervalSince(lastPlaybackEnd) < Self.echoTail }
    }

    /// Speech RMS is small; this spreads it over 0…1 for animations.
    private static func level(rms: Float) -> Float {
        min(1, rms * 8)
    }
}

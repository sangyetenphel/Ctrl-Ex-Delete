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
/// Callbacks run on audio threads, so this type isn't tied to the main actor.
nonisolated final class CallAudio: @unchecked Sendable {
    static let captureRate: Double = 16_000
    static let playbackRate: Double = 24_000

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
    private var converter: AVAudioConverter?
    private var isRunning = false

    func start(speakerOn: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
        try session.setActive(true)
        setSpeaker(speakerOn)

        // Echo cancellation. Not available in every environment (e.g. some
        // simulators), where the call still works without it.
        try? engine.inputNode.setVoiceProcessingEnabled(true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: captureFormat)
        let chunk = AVAudioFrameCount(inputFormat.sampleRate / 10)  // ~100 ms
        input.installTap(onBus: 0, bufferSize: chunk, format: inputFormat) { [weak self] buffer, _ in
            self?.capture(buffer)
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        engine.prepare()
        try engine.start()
        player.play()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Speaker (on) or the phone's earpiece / connected headphones (off).
    func setSpeaker(_ on: Bool) {
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(on ? .speaker : .none)
    }

    // MARK: Ced's voice

    /// Queues one chunk of Ced's voice (16-bit little-endian PCM, 24 kHz, mono).
    func play(_ pcm: Data) {
        guard isRunning else { return }
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
        player.scheduleBuffer(buffer, completionHandler: nil)
        onPlaybackLevel?(Self.level(rms: (sumOfSquares / Float(frames)).squareRoot()))
    }

    /// Drops everything still queued (the user started talking over Ced).
    func stopPlayback() {
        guard isRunning else { return }
        player.stop()
        player.play()
        onPlaybackLevel?(0)
    }

    // MARK: Microphone

    private func capture(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let onCapture else { return }
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
        let data = Data(bytes: samples, count: count * MemoryLayout<Int16>.size)
        onCapture(data, Self.level(rms: (sumOfSquares / Float(count)).squareRoot()))
    }

    /// Speech RMS is small; this spreads it over 0…1 for animations.
    private static func level(rms: Float) -> Float {
        min(1, rms * 8)
    }
}

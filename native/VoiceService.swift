import AVFoundation
import Foundation
import Speech

/// All public methods and emitted events run on the main thread. Audio buffers stay on this Mac.
final class VoiceService: NSObject, AVAudioPlayerDelegate {
    /// A successful capture transfers ownership of a private 16 kHz mono WAV to this callback.
    /// No final transcript event is emitted when this callback handles verification.
    var onCapturedSpeech: ((String, URL) -> Void)?
    var recognitionLocale: String?
    private let emit: (String, [String: Any]) -> Void
    private var listeningID: UUID?
    private var listeningIsStarting = false
    private var awaitingFinalTranscript = false
    private var receivedFinalTranscript = false
    private var isEnrollment = false
    private var transcript = ""
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var engine: AVAudioEngine?
    private var capture: MicrophoneCapture?
    private var inputTapInstalled = false
    private var microphoneMeter: Timer?
    private var finalTranscriptTimer: Timer?
    private var maximumListeningTimer: Timer?

    private var speechID: UUID?
    private var synthesizer: AVSpeechSynthesizer?
    private var renderer: SpeechFileRenderer?
    private var player: AVAudioPlayer?
    private var playbackMeter: Timer?
    private var synthesisTimeout: Timer?
    private var isShutDown = false

    init(emit: @escaping (String, [String: Any]) -> Void) {
        self.emit = emit
        super.init()
    }

    func startListening(enrollment: Bool = false) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isShutDown, listeningID == nil else { return }
        stopSpeaking()
        let id = UUID()
        listeningID = id
        listeningIsStarting = true
        isEnrollment = enrollment
        receivedFinalTranscript = false
        transcript = ""
        emit("transcript", ["text": "", "final": false])
        emit("listening", ["active": false, "starting": true])

        // Neither permission is requested at launch; this path follows a user's microphone action.
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            requestMicrophone(for: id)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    guard let self = self, self.listeningID == id else { return }
                    if status == .authorized {
                        self.requestMicrophone(for: id)
                    } else {
                        self.failListening(id, "Speech recognition permission is needed. Allow JARVIS in System Settings → Privacy & Security → Speech Recognition.")
                    }
                }
            }
        case .denied, .restricted:
            failListening(id, "Speech recognition permission is needed. Allow JARVIS in System Settings → Privacy & Security → Speech Recognition.")
        @unknown default:
            failListening(id, "Speech recognition is unavailable on this Mac.")
        }
    }

    func stopListening(submit: Bool = true) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let id = listeningID else { return }
        if !submit || listeningIsStarting {
            finishListening(id, submit: false)
            return
        }
        guard !awaitingFinalTranscript else { return }
        awaitingFinalTranscript = true
        stopMicrophone()
        emit("listening", ["active": false, "starting": false, "finalizing": true])
        if receivedFinalTranscript {
            finishListening(id, submit: true)
            return
        }
        // End audio before cancelling the task so the last spoken word can reach the recognizer.
        finalTranscriptTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            self?.finishListening(id, submit: true)
        }
    }

    func speak(_ text: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isShutDown else { return }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        stopListening(submit: false)
        stopSpeaking()

        let installed = AVSpeechSynthesisVoice.speechVoices()
        let english = installed.filter { voice in
            guard voice.language == "en-GB" || voice.language == "en-US" else { return false }
            if #available(macOS 14.0, *), voice.voiceTraits.contains(.isPersonalVoice) { return false }
            return true
        }
        let voice = english.sorted { lhs, rhs in
            func score(_ voice: AVSpeechSynthesisVoice) -> Int {
                let language = voice.language == "en-GB" ? 100 : 0
                let quality = voice.quality.rawValue * 10
                return language + quality + (voice.name == "Daniel" ? 5 : 0)
            }
            if score(lhs) == score(rhs) { return lhs.identifier < rhs.identifier }
            return score(lhs) > score(rhs)
        }.first
        guard let voice = voice else {
            emit("error", ["message": "No local English voice is available. Add an English voice in System Settings → Accessibility, then try again."])
            return
        }

        let id = UUID()
        speechID = id
        let render = SpeechFileRenderer { [weak self] result in
            guard let self = self, self.speechID == id else { return }
            self.synthesisTimeout?.invalidate()
            self.synthesisTimeout = nil
            switch result {
            case .success(let url): self.playSpeech(at: url, id: id)
            case .failure(let error): self.failSpeaking(id, "Could not create local speech: \(error.localizedDescription)")
            }
        }
        renderer = render
        let synth = AVSpeechSynthesizer()
        synthesizer = synth
        let utterance = AVSpeechUtterance(string: words)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.93
        utterance.pitchMultiplier = 0.78
        utterance.volume = 1
        emit("speech", ["active": true])
        emit("amplitude", ["value": 0.0])
        synthesisTimeout = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in
            self?.failSpeaking(id, "The local voice took too long to respond. Try a shorter response or choose another English voice in System Settings → Accessibility.")
        }
        // Rendering gives AVAudioPlayer real PCM audio to meter; no simulated animation envelope.
        synth.write(utterance) { buffer in render.consume(buffer) }
    }

    func stopSpeaking() {
        dispatchPrecondition(condition: .onQueue(.main))
        let wasActive = speechID != nil
        speechID = nil // Invalidates already-enqueued render callbacks before cancelling the synthesizer.
        synthesisTimeout?.invalidate()
        synthesisTimeout = nil
        playbackMeter?.invalidate()
        playbackMeter = nil
        player?.delegate = nil
        player?.stop()
        player = nil
        renderer?.cancel()
        renderer = nil
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        if wasActive {
            emit("speech", ["active": false])
            emit("amplitude", ["value": 0.0])
        }
    }

    func shutdown() {
        dispatchPrecondition(condition: .onQueue(.main))
        isShutDown = true
        stopListening(submit: false)
        stopSpeaking()
    }

    private func requestMicrophone(for id: UUID) {
        guard listeningID == id else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginRecognition(id)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self = self, self.listeningID == id else { return }
                    if allowed { self.beginRecognition(id) }
                    else { self.failListening(id, "Microphone access is needed. Allow JARVIS in System Settings → Privacy & Security → Microphone.") }
                }
            }
        case .denied, .restricted:
            failListening(id, "Microphone access is needed. Allow JARVIS in System Settings → Privacy & Security → Microphone.")
        @unknown default:
            failListening(id, "Microphone access is unavailable on this Mac.")
        }
    }

    private func beginRecognition(_ id: UUID) {
        guard listeningID == id else { return }
        let candidates = Self.recognitionLocales(preferred: Locale.preferredLanguages, override: recognitionLocale)
            .compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
        guard let recognizer = candidates.first(where: { $0.supportsOnDeviceRecognition && $0.isAvailable }) else {
            failListening(id, "Offline English speech recognition is unavailable. Enable English Dictation in System Settings → Keyboard and let its language files finish downloading, then try again. JARVIS will not send microphone audio to a cloud service.")
            return
        }
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = ["Fardeen", "Jarvis", "JARVIS", "Ollama", "Safari", "Chrome", "Finder", "VS Code", "Terminal", "System Settings", "Spotify", "volume", "system status"]
        if #available(macOS 13.0, *) { request.addsPunctuation = true }
        let capture = MicrophoneCapture(request: request)
        self.capture = capture
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            failListening(id, "No usable microphone was found. Select an input device in System Settings → Sound, then try again.")
            return
        }
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, self.listeningID == id else { return }
                if let result = result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.receivedFinalTranscript = true
                        // Enrollment records a complete sample until Fardeen stops or the time limit,
                        // even if Dictation considers an early pause the end of an utterance.
                        if self.isEnrollment && !self.awaitingFinalTranscript {
                            self.emit("transcript", ["text": self.transcript, "final": false])
                            return
                        }
                        let confidences = result.bestTranscription.segments.map(\.confidence).filter { $0 > 0 }
                        if !confidences.isEmpty && confidences.reduce(0, +) / Float(confidences.count) < 0.35 {
                            self.failListening(id, "I’m not confident I heard that correctly. Please repeat the full request clearly, or type it.")
                            return
                        }
                        self.finishListening(id, submit: true)
                        return
                    }
                    self.emit("transcript", ["text": self.transcript, "final": false])
                }
                if let error = error {
                    if self.isEnrollment && self.receivedFinalTranscript { return }
                    if self.awaitingFinalTranscript {
                        self.finishListening(id, submit: true)
                    } else {
                        let nsError = error as NSError
                        let message = nsError.code == 1110
                            ? "I didn’t catch any words. Try again and speak a little closer to your microphone."
                            : "On-device speech recognition stopped: \(error.localizedDescription) Try again, or check English Dictation in System Settings → Keyboard."
                        self.failListening(id, message)
                    }
                }
            }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            capture.append(buffer)
        }
        inputTapInstalled = true
        do {
            engine.prepare()
            try engine.start()
            listeningIsStarting = false
            emit("listening", ["active": true, "starting": false, "locale": recognizer.locale.identifier])
            maximumListeningTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                guard let self = self, self.listeningID == id else { return }
                self.stopListening(submit: true)
            }
            microphoneMeter = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self = self, self.listeningID == id, !self.awaitingFinalTranscript else { return }
                self.emit("amplitude", ["value": capture.amplitude])
            }
        } catch {
            failListening(id, "Could not start the microphone: \(error.localizedDescription)")
        }
    }

    private func stopMicrophone() {
        maximumListeningTimer?.invalidate()
        maximumListeningTimer = nil
        microphoneMeter?.invalidate()
        microphoneMeter = nil
        engine?.stop()
        if inputTapInstalled {
            engine?.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        capture?.endAudio()
        engine = nil
        emit("amplitude", ["value": 0.0])
    }

    private func finishListening(_ id: UUID, submit: Bool) {
        guard listeningID == id else { return }
        let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        listeningID = nil // A final result, timeout, and cancellation can never submit twice.
        listeningIsStarting = false
        awaitingFinalTranscript = false
        finalTranscriptTimer?.invalidate()
        finalTranscriptTimer = nil
        stopMicrophone()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizer = nil
        let recordedCapture = capture
        capture = nil
        transcript = ""
        emit("listening", ["active": false, "starting": false])
        if submit {
            if words.isEmpty {
                emit("error", ["message": "I didn’t catch any words. Try again and speak a little closer to your microphone."])
            } else if let callback = onCapturedSpeech, let recordedCapture = recordedCapture {
                do {
                    let url = try recordedCapture.exportAudio()
                    emit("transcript", ["text": words, "final": false])
                    callback(words, url)
                } catch {
                    emit("error", ["message": "Could not prepare audio for owner verification: \(error.localizedDescription)"])
                }
            } else {
                emit("transcript", ["text": words, "final": true])
            }
        }
    }

    private func failListening(_ id: UUID, _ message: String) {
        guard listeningID == id else { return }
        finishListening(id, submit: false)
        emit("error", ["message": message])
    }

    private func playSpeech(at url: URL, id: UUID) {
        guard speechID == id else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            self.player = player
            player.delegate = self
            player.isMeteringEnabled = true
            player.prepareToPlay()
            guard player.play() else {
                failSpeaking(id, "The local voice could not start playback. Check your sound output device.")
                return
            }
            playbackMeter = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self, weak player] _ in
                guard let self = self, self.speechID == id, let player = player else { return }
                player.updateMeters()
                var power: Float = -160
                for channel in 0..<player.numberOfChannels {
                    power = max(power, player.averagePower(forChannel: channel))
                }
                self.emit("amplitude", ["value": Self.normalizedPower(Double(power))])
            }
        } catch {
            failSpeaking(id, "Could not play the local voice: \(error.localizedDescription)")
        }
    }

    private func failSpeaking(_ id: UUID, _ message: String) {
        guard speechID == id else { return }
        stopSpeaking()
        emit("error", ["message": message])
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.player === player, let id = self.speechID else { return }
            if flag { self.stopSpeaking() }
            else { self.failSpeaking(id, "Voice playback was interrupted. Check your sound output and try again.") }
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.player === player, let id = self.speechID else { return }
            self.failSpeaking(id, "Could not decode the local voice audio. Please try again.")
        }
    }

    fileprivate static func normalizedPower(_ decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return min(1, max(0, (decibels + 55) / 55))
    }

    static func recognitionLocales(preferred: [String], override: String?) -> [String] {
        var locales: [String] = []
        for value in [override].compactMap({ $0 }) + preferred + ["en-US", "en-GB", "en-IN", "en-AU"] {
            let normalized = value.replacingOccurrences(of: "_", with: "-")
            guard normalized == "en" || normalized.hasPrefix("en-") else { continue }
            let identifier = normalized == "en" ? "en-US" : normalized
            if !locales.contains(identifier) { locales.append(identifier) }
        }
        return locales
    }
}

/// The audio render thread never reads VoiceService's main-thread state.
final class MicrophoneCapture {
    private let lock = NSLock()
    private let request: SFSpeechAudioBufferRecognitionRequest
    private var active = true
    private var level = 0.0
    private var samples: [Float] = []
    private var sampleRate = 0.0

    init(request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }

    var amplitude: Double {
        lock.lock()
        defer { lock.unlock() }
        return level
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return }
        request.append(buffer)
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else {
            level = 0
            return
        }
        let channelCount = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        if sampleRate == 0 {
            sampleRate = buffer.format.sampleRate
            samples.reserveCapacity(Int(sampleRate * 30))
        }
        guard buffer.format.sampleRate == sampleRate else { return }
        let remaining = max(0, Int(sampleRate * 30) - samples.count)
        var sum = 0.0
        for frame in 0..<frames {
            var mono: Float = 0
            for channel in 0..<channelCount {
                let sample = buffer.format.isInterleaved ? channels[0][frame * channelCount + channel] : channels[channel][frame]
                let safeSample: Float = sample.isFinite ? sample : 0
                mono += safeSample / Float(channelCount)
                sum += Double(safeSample * safeSample)
            }
            if frame < remaining { samples.append(mono) }
        }
        let rms = sqrt(sum / Double(frames * channelCount))
        level = VoiceService.normalizedPower(20 * log10(max(rms, 0.00000001)))
    }

    func endAudio() {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return }
        active = false
        level = 0
        request.endAudio()
    }

    /// Export after the tap has stopped; no file I/O runs on the real-time audio thread.
    func exportAudio() throws -> URL {
        lock.lock()
        let recorded = samples
        let rate = sampleRate
        lock.unlock()
        guard !recorded.isEmpty, rate > 0,
              let inputFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(recorded.count)),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(ceil(Double(recorded.count) * 16000 / rate)) + 64),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw NSError(domain: "JARVISVoice", code: 3, userInfo: [NSLocalizedDescriptionKey: "No usable microphone audio was captured."])
        }
        input.frameLength = AVAudioFrameCount(recorded.count)
        recorded.withUnsafeBufferPointer { source in input.floatChannelData![0].update(from: source.baseAddress!, count: recorded.count) }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied { inputStatus.pointee = .endOfStream; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0 else {
            throw conversionError ?? NSError(domain: "JARVISVoice", code: 4, userInfo: [NSLocalizedDescriptionKey: "Microphone audio could not be resampled."])
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-owner-\(UUID().uuidString).wav")
        // Create with owner-only access before writing, so there is no readable-permission window.
        guard FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: [.posixPermissions: 0o600]) else {
            throw NSError(domain: "JARVISVoice", code: 5, userInfo: [NSLocalizedDescriptionKey: "A private audio file could not be created."])
        }
        do {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: output)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}

/// Low-level ring modulation adds a metallic timbre while keeping the natural voice intelligible.
/// A single oscillator spans render buffers, avoiding clicks at synthesis callback boundaries.
final class RobotSpeechEffect {
    private var phase = 0.0

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, buffer.format.sampleRate > 0 else { return }
        let count = Int(buffer.format.channelCount)
        let step = 2 * Double.pi * 82 / buffer.format.sampleRate
        for frame in 0..<Int(buffer.frameLength) {
            let gain = Float(0.78 + 0.22 * sin(phase))
            for channel in 0..<count {
                if buffer.format.isInterleaved {
                    let index = frame * count + channel
                    channels[0][index] = max(-1, min(1, channels[0][index] * gain))
                } else {
                    channels[channel][frame] = max(-1, min(1, channels[channel][frame] * gain))
                }
            }
            phase += step
            if phase >= 2 * .pi { phase -= 2 * .pi }
        }
    }
}

/// Each synthesis owns a unique temporary file. Cancelling invalidates both writing and playback.
private final class SpeechFileRenderer {
    private let lock = NSLock()
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-voice-\(UUID().uuidString).caf")
    private var file: AVAudioFile?
    private var finished = false
    private var cancelled = false
    private var wroteFrames = false
    private let robotEffect = RobotSpeechEffect()
    private let completion: (Result<URL, Error>) -> Void

    init(completion: @escaping (Result<URL, Error>) -> Void) { self.completion = completion }

    func consume(_ buffer: AVAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, !finished else { return }
        guard let pcm = buffer as? AVAudioPCMBuffer else {
            finish(.failure(NSError(domain: "JARVISVoice", code: 1, userInfo: [NSLocalizedDescriptionKey: "The voice returned an unsupported audio format."])))
            return
        }
        if pcm.frameLength == 0 {
            file = nil // Close the CAF before allowing playback to open it.
            if wroteFrames { finish(.success(url)) }
            else { finish(.failure(NSError(domain: "JARVISVoice", code: 2, userInfo: [NSLocalizedDescriptionKey: "The selected voice produced no audio."]))) }
            return
        }
        do {
            robotEffect.process(pcm)
            if file == nil {
                file = try AVAudioFile(forWriting: url, settings: pcm.format.settings, commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
            }
            try file?.write(from: pcm)
            wroteFrames = true
        } catch {
            file = nil
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        finished = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let deliver = !self.cancelled
            self.lock.unlock()
            if deliver { self.completion(result) }
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        file = nil
        try? FileManager.default.removeItem(at: url)
        lock.unlock()
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

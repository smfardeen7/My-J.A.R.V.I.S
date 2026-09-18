import AVFoundation
import Foundation
import Speech

@main
struct VoiceTests {
    static func main() throws {
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }
        check(VoiceService.recognitionLocales(preferred: ["en-IN", "en-US"], override: nil).first == "en-IN", "Respect the user's English locale")
        check(VoiceService.recognitionLocales(preferred: ["fr-FR"], override: "en-GB").first == "en-GB", "Respect the selected English locale")
        check(!VoiceService.recognitionLocales(preferred: ["en-US", "en_US"], override: nil).dropFirst().contains("en-US"), "Do not retry duplicate locales")
        check(VoiceService.recognitionLocales(preferred: ["fr-FR"], override: "nonsense").first == "en-US", "Invalid preferences fall back to English")

        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
        pcm.frameLength = 4800
        for i in 0..<4800 { pcm.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 48000)) * 0.8 }
        let original = Array(UnsafeBufferPointer(start: pcm.floatChannelData![0], count: 4800))
        let effect = RobotSpeechEffect()
        effect.process(pcm)
        let changed = Array(UnsafeBufferPointer(start: pcm.floatChannelData![0], count: 4800))
        check(zip(original, changed).contains { abs($0 - $1) > 0.02 }, "Robot output must differ from the natural voice")
        check(changed.allSatisfy { $0.isFinite && abs($0) <= 1 }, "The robot effect must not clip or emit nonfinite samples")
        for i in 0..<4800 { pcm.floatChannelData![0][i] = 0 }
        RobotSpeechEffect().process(pcm)
        check((0..<4800).allSatisfy { pcm.floatChannelData![0][$0] == 0 }, "Silence must stay silent")

        let capture = MicrophoneCapture(request: SFSpeechAudioBufferRecognitionRequest())
        // Synthetic audio only: these tests never open the microphone or play sound.
        for i in 0..<4800 { pcm.floatChannelData![0][i] = original[i] }
        for _ in 0..<12 { capture.append(pcm) }
        capture.endAudio()
        let url = try capture.exportAudio()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        check(file.fileFormat.sampleRate == 16000, "Verifier audio must be 16 kHz")
        check(file.fileFormat.channelCount == 1, "Verifier audio must be mono")
        check(abs(Double(file.length) / file.fileFormat.sampleRate - 1.2) < 0.02, "Resampling must preserve recording duration")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Temporary voice recordings must be private")
        let bounded = MicrophoneCapture(request: SFSpeechAudioBufferRecognitionRequest())
        for _ in 0..<310 { bounded.append(pcm) }
        bounded.endAudio()
        let boundedURL = try bounded.exportAudio()
        defer { try? FileManager.default.removeItem(at: boundedURL) }
        let boundedFile = try AVAudioFile(forReading: boundedURL)
        check(Double(boundedFile.length) / boundedFile.fileFormat.sampleRate <= 30.01, "Capture must be bounded to thirty seconds")
        print("Voice checks passed: \(checks)")
    }
}

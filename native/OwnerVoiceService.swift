import Foundation
import Security
import LocalAuthentication
import Darwin

enum OwnerVoiceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

final class OwnerVoiceService {
    private struct Embedding: Decodable {
        let embedding: [Double]
        let duration: Double
        let speech_duration: Double
        let model_id: String
    }
    private let runtime = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/JARVIS/voice-runtime")
    private let worker = Bundle.main.resourceURL!.appendingPathComponent("speaker-worker.py")
    private let keychainQuery: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.smfardeen.jarvis.owner-voice", kSecAttrAccount as String: "Fardeen"]
    private var process: Process?
    private var activeRecording: URL?
    private var generation = UUID()
    private(set) var profile: SpeakerProfile?
    private(set) var pendingSamples: [[Double]] = []
    private(set) var enrolling = false
    private var enrollmentExpiry = Date.distantPast
    var enrolled: Bool { profile?.isValid == true }
    var sampleCount: Int { pendingSamples.count }
    var runtimeReady: Bool {
        FileManager.default.isExecutableFile(atPath: runtime.appendingPathComponent("venv/bin/python3").path) &&
        FileManager.default.fileExists(atPath: runtime.appendingPathComponent("models/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx").path) &&
        FileManager.default.fileExists(atPath: runtime.appendingPathComponent("models/silero_vad.onnx").path) &&
        FileManager.default.fileExists(atPath: worker.path)
    }
    var enrollmentIsAuthorized: Bool { enrolling && Date() < enrollmentExpiry }
    static let phrases = [
        "Hello Jarvis, my name is Fardeen. This is my natural voice, and I am setting up my personal assistant on this Mac.",
        "Jarvis, help me plan my day. I would like clear answers, useful information, and careful confirmation before changing my Mac.",
        "This is Fardeen speaking again. The weather changes, the clock keeps moving, and my assistant is ready to help me today."
    ]
    var phrase: String { Self.phrases[min(sampleCount, 2)] }

    init() {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext(); context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
           let profile = try? JSONDecoder().decode(SpeakerProfile.self, from: data), profile.isValid { self.profile = profile }
    }

    /// Called only after a successful Touch ID challenge in the controller.
    func beginEnrollment() {
        cancel(); pendingSamples = []; enrolling = true; enrollmentExpiry = Date().addingTimeInterval(300)
    }
    func endEnrollment() { cancel(); pendingSamples = []; enrolling = false; enrollmentExpiry = .distantPast }
    func cancel() {
        generation = UUID()
        if let recording = activeRecording { try? FileManager.default.removeItem(at: recording) }
        activeRecording = nil
        if let task = process, task.isRunning {
            task.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if task.isRunning { kill(task.processIdentifier, SIGKILL) }
            }
        }
        process = nil
    }

    func forget() throws {
        endEnrollment()
        let status = SecItemDelete(keychainQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw OwnerVoiceError.message("Could not delete the saved voice profile from Keychain.") }
        profile = nil
    }

    /// Owns the recording: always removes it after worker completion or failure.
    func consume(_ audio: URL, enrollment: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
        precondition(Thread.isMainThread)
        cancel()
        guard runtimeReady else { try? FileManager.default.removeItem(at: audio); completion(.failure(OwnerVoiceError.message("The local voice model is unavailable. Voice commands stay locked; run the voice setup installer."))); return }
        guard enrollment ? enrollmentIsAuthorized : enrolled else { try? FileManager.default.removeItem(at: audio); completion(.failure(OwnerVoiceError.message("Enroll Fardeen's voice first. Enrollment requires Touch ID."))); return }
        let token = generation
        let task = Process()
        task.executableURL = runtime.appendingPathComponent("venv/bin/python3")
        task.arguments = ["-I", worker.path, "--model", runtime.appendingPathComponent("models/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx").path, "--audio", audio.path]
        task.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "PYTHONNOUSERSITE": "1", "OMP_NUM_THREADS": "2"]
        let output = Pipe()
        task.standardOutput = output; task.standardError = FileHandle.nullDevice
        do { try task.run(); process = task; activeRecording = audio }
        catch { try? FileManager.default.removeItem(at: audio); completion(.failure(OwnerVoiceError.message("The local voice verifier could not start. Voice commands stay locked."))); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self = self, self.generation == token, self.process === task else { return }
            self.cancel()
            completion(.failure(OwnerVoiceError.message("Voice verification timed out. Please try again.")))
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            try? FileManager.default.removeItem(at: audio)
            DispatchQueue.main.async {
                guard let self = self, self.generation == token else { return }
                self.process = nil
                self.activeRecording = nil
                guard data.count <= 100_000 else { completion(.failure(OwnerVoiceError.message("Invalid voice verification result."))); return }
                guard task.terminationStatus == 0, let value = try? JSONDecoder().decode(Embedding.self, from: data), value.model_id == SpeakerProfile.modelID,
                      let vector = SpeakerProfile.normalized(value.embedding), value.duration.isFinite, value.speech_duration.isFinite else {
                    let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                    completion(.failure(OwnerVoiceError.message(String((message ?? "Could not verify this recording. Speak clearly for at least four seconds in a quiet room.").prefix(300))))); return
                }
                guard value.speech_duration >= (enrollment ? 4 : 3) else { completion(.failure(OwnerVoiceError.message("Please speak for at least \(enrollment ? "four" : "three") seconds so I can check your voice."))); return }
                if enrollment {
                    guard self.enrollmentIsAuthorized else { completion(.failure(OwnerVoiceError.message("Enrollment expired. Start again with Touch ID."))); return }
                    if !self.pendingSamples.isEmpty && !SpeakerProfile.consistent(vector, with: self.pendingSamples) {
                        completion(.failure(OwnerVoiceError.message("This sample does not match the earlier voice sample closely enough. Use your natural voice and the same microphone, then retry."))); return
                    }
                    let samples = self.pendingSamples + [vector]
                    if samples.count == 3 {
                        let profile = SpeakerProfile(modelID: SpeakerProfile.modelID, samples: samples)
                        do { try self.save(profile); self.profile = profile; self.pendingSamples = []; self.enrolling = false; self.enrollmentExpiry = .distantPast }
                        catch { completion(.failure(error)); return }
                    } else { self.pendingSamples = samples }
                    completion(.success(true))
                } else { completion(.success(self.profile?.matches(vector) == true)) }
            }
        }
    }
    private func save(_ profile: SpeakerProfile) throws {
        guard profile.isValid else { throw OwnerVoiceError.message("The three voice samples are not consistent. Please enroll again.") }
        let data = try JSONEncoder().encode(profile)
        var status = SecItemUpdate(keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = keychainQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw OwnerVoiceError.message("Could not securely save the voice profile in Keychain. " + (enrolled ? "Your existing voice profile was kept." : "Voice commands remain locked.")) }
    }
}

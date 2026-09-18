import Foundation

@main enum OwnerVoiceTests {
    static func main() throws {
        var checks = 0
        func expect(_ value: Bool, _ label: String) { checks += 1; if !value { print("FAIL: \(label)"); exit(1) } }
        let first = [1.0] + Array(repeating: 0.0, count: 191)
        let other = [0.0, 1.0] + Array(repeating: 0.0, count: 190)
        let profile = SpeakerProfile(modelID: SpeakerProfile.modelID, samples: [first, first, first])
        expect(profile.isValid, "three valid normalized enrollment vectors")
        expect(profile.matches(first), "matching voice accepted")
        expect(!profile.matches(other), "unrelated voice rejected")
        expect(!profile.matches([]), "empty candidate rejected")
        expect(!profile.matches(Array(repeating: 0, count: 192)), "zero vector rejected")
        expect(!profile.matches([Double.nan] + Array(repeating: 0, count: 191)), "nonfinite candidate rejected")
        expect(!SpeakerProfile(modelID: "different-model", samples: [first, first, first]).isValid, "model mismatch invalidates enrollment")
        expect(!SpeakerProfile(modelID: SpeakerProfile.modelID, samples: [first, first]).matches(first), "incomplete enrollment stays locked")
        expect(!SpeakerProfile(modelID: SpeakerProfile.modelID, samples: [first, first, other]).isValid, "inconsistent enrollment rejected")
        expect(SpeakerProfile.consistent(first, with: [first]), "consistent enrollment sample")
        expect(!SpeakerProfile.consistent(other, with: [first]), "different enrollment speaker rejected")
        let decoded = try JSONDecoder().decode(SpeakerProfile.self, from: JSONEncoder().encode(profile))
        expect(decoded.matches(first), "profile survives serialization")
        print("\(checks) owner profile checks passed; no microphone, authentication or Keychain access.")
    }
}

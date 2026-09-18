import Foundation

/// Similarity is a probabilistic filter, not identity proof or replay detection.
struct SpeakerProfile: Codable {
    static let modelID = "3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced"
    static let dimensions = 192
    let modelID: String
    let samples: [[Double]]

    var isValid: Bool {
        guard modelID == Self.modelID, samples.count == 3, samples.allSatisfy({ Self.normalized($0) != nil }) else { return false }
        return samples.indices.allSatisfy { index in
            Self.consistent(samples[index], with: samples.enumerated().filter { $0.offset != index }.map(\.element))
        }
    }
    func matches(_ candidate: [Double]) -> Bool {
        guard isValid else { return false }
        return Self.consistent(candidate, with: samples)
    }
    static func consistent(_ candidate: [Double], with samples: [[Double]]) -> Bool {
        guard let candidate = normalized(candidate), !samples.isEmpty else { return false }
        let scores = samples.compactMap { sample -> Double? in
            guard let sample = normalized(sample) else { return nil }
            return zip(candidate, sample).reduce(0) { $0 + $1.0 * $1.1 }
        }
        // Initial conservative operating point, not a calibrated security guarantee.
        return scores.count == samples.count && (scores.min() ?? -1) >= 0.60 && scores.reduce(0, +) / Double(scores.count) >= 0.70
    }
    static func normalized(_ values: [Double]) -> [Double]? {
        guard values.count == dimensions, values.allSatisfy(\.isFinite) else { return nil }
        let length = sqrt(values.reduce(0) { $0 + $1 * $1 })
        guard length.isFinite, length > 0.000001 else { return nil }
        return values.map { $0 / length }
    }
}

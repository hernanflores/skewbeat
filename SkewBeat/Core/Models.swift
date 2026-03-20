import Foundation
import Observation

struct Channel: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var steps: [Bool] = Array(repeating: false, count: 16)
    var length: Int = 16
    var currentStep: Int = 0
    var midiNote: Int = 60
    var midiChannel: Int = 1
    var trigProb: Double = 1.0
    var addProb: Double = 0.0
}

@Observable
final class Sequencer: Codable {
    var channels: [Channel] = (0..<12).map { i in
        Channel(name: "Channel \(i + 1)")
    }
    var bpm: Double = 120
    var isPlaying: Bool = false
    var swing: Double = 0.0

    init() {}

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case channels, bpm, isPlaying, swing
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        channels = try container.decode([Channel].self, forKey: .channels)
        bpm = try container.decode(Double.self, forKey: .bpm)
        isPlaying = try container.decode(Bool.self, forKey: .isPlaying)
        swing = try container.decode(Double.self, forKey: .swing)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(channels, forKey: .channels)
        try container.encode(bpm, forKey: .bpm)
        try container.encode(isPlaying, forKey: .isPlaying)
        try container.encode(swing, forKey: .swing)
    }
}

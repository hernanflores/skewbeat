import Foundation
import Observation

// MARK: - CCKnob
//
// A single CC automation lane attached to a Channel.
// On each tick, the engine evaluates sendProb and fires a CC value within
// the symmetric window [homeValue - offset, homeValue + offset] (clamped 0–127).
//
// midiChannel is copied from the parent Channel at knob creation time.
// It is NOT auto-synced if the parent Channel's midiChannel changes later —
// this allows per-knob MIDI channel routing as an intentional override.

struct CCKnob: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var ccNumber: Int = 1        // 0–127
    var homeValue: Int = 64      // 0–127, centre of the output range
    var offset: Int = 0          // 0–63, symmetric: sends homeValue ± offset
    var sendProb: Double = 1.0   // 0.0–1.0 probability gate per tick
    var midiChannel: Int = 1     // 1–16

    /// Default array of 8 knobs mapped to CC numbers 1–8.
    /// sendProb is 0.25 by default — sparse CC firing avoids saturating MIDI 1.0 bandwidth
    /// (12 channels × 8 knobs × sendProb=1.0 @ 120 BPM ≈ 74% of the 31.25 kbaud budget).
    static let defaults: [CCKnob] = (1...8).map { n in
        var k = CCKnob()
        k.ccNumber = n
        k.sendProb = 0.25
        return k
    }
}

// MARK: - Channel
//
// Data model for a single sequencer track.
//
// steps[] is always Channel.maxSteps elements; `length` controls how many
// are active (the display/playback window). knobs are always exactly 8
// per channel — the engine iterates all 8 on every tick unconditionally.

struct Channel: Codable, Identifiable {
    /// Maximum number of steps a channel can hold. Shared constant across engine and UI.
    static let maxSteps = 32

    var id: UUID = UUID()
    var name: String = ""
    /// Always `maxSteps` elements; `length` controls how many are active (display window).
    var steps: [Bool] = Array(repeating: false, count: Channel.maxSteps)
    var length: Int = 16
    var currentStep: Int = 0
    var midiNote: Int = 60
    var midiChannel: Int = 1
    var trigProb: Double = 1.0
    var addProb: Double = 0.0
    /// CC automation knobs. Always exactly 8. Loaded from presets; default-injected for
    /// old presets that pre-date knob support (see init(from:) migration below).
    var knobs: [CCKnob] = CCKnob.defaults

    // MARK: Inits

    init() {}

    init(name: String) {
        self.name = name
    }

    // MARK: - Codable
    //
    // Explicit implementation required to provide a migration fallback for `knobs`:
    // presets saved before knob support was added will not have a "knobs" key in JSON.
    // decodeIfPresent returns nil for missing keys; we substitute CCKnob.defaults.

    private enum CodingKeys: String, CodingKey {
        case id, name, steps, length, currentStep
        case midiNote, midiChannel, trigProb, addProb, knobs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self,    forKey: .id)
        name        = try c.decode(String.self,  forKey: .name)
        steps       = try c.decode([Bool].self,  forKey: .steps)
        length      = try c.decode(Int.self,     forKey: .length)
        currentStep = try c.decode(Int.self,     forKey: .currentStep)
        midiNote    = try c.decode(Int.self,     forKey: .midiNote)
        midiChannel = try c.decode(Int.self,     forKey: .midiChannel)
        trigProb    = try c.decode(Double.self,  forKey: .trigProb)
        addProb     = try c.decode(Double.self,  forKey: .addProb)
        // Migration: old presets won't have "knobs" — inject defaults rather than crash.
        knobs = (try? c.decodeIfPresent([CCKnob].self, forKey: .knobs)) ?? CCKnob.defaults
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,          forKey: .id)
        try c.encode(name,        forKey: .name)
        try c.encode(steps,       forKey: .steps)
        try c.encode(length,      forKey: .length)
        try c.encode(currentStep, forKey: .currentStep)
        try c.encode(midiNote,    forKey: .midiNote)
        try c.encode(midiChannel, forKey: .midiChannel)
        try c.encode(trigProb,    forKey: .trigProb)
        try c.encode(addProb,     forKey: .addProb)
        try c.encode(knobs,       forKey: .knobs)
    }
}

// MARK: - Sequencer

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

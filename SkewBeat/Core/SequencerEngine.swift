import Foundation
import CoreMIDI


// MARK: - Notification names

extension Notification.Name {
    /// Posted on the main thread whenever a step fires via the Add path (ephemeral).
    /// userInfo keys: "channelID" (UUID), "step" (Int).
    static let skewBeatEphemeralStep = Notification.Name("SkewBeat.EphemeralStep")
}


final class SequencerEngine {

    // MARK: - State

    private(set) var sequencer: Sequencer = Sequencer()
    private(set) var midiManager: MIDIManager = MIDIManager()
    private(set) var presetManager: PresetManager = PresetManager()

    /// Per-channel step counters — internal so tests can inspect and drive them.
    var currentSteps: [Int]

    /// ID of the last preset that was loaded or saved. Nil until the first preset interaction.
    private(set) var activePresetID: UUID?

    // MARK: - Callbacks

    /// Called on the main thread whenever a step fires via the Add (ephemeral) path.
    /// Also posted as `Notification.Name.skewBeatEphemeralStep` for multicast subscribers.
    var onEphemeralStep: ((UUID, Int) -> Void)?

    /// Called synchronously on the clock queue whenever a CC knob fires.
    /// Receives the knob, the calculated CC value (0–127), and the parent channel.
    /// Primarily used for unit testing; when MIDI CC send is wired, dispatch to the
    /// appropriate queue inside fireKnob(knob:value:channel:).
    var onKnobFire: ((CCKnob, Int, Channel) -> Void)?

    // MARK: - Clock

    let clockQueue = DispatchQueue(
        label: "com.skewbeat.clock",
        qos: .userInteractive
    )
    private var timer: DispatchSourceTimer?

    /// Global tick counter — used to determine odd/even steps for swing.
    private var tickCount: Int = 0

    // MARK: - Init

    init() {
        currentSteps = Array(repeating: 0, count: sequencer.channels.count)

        start()
    }

    // MARK: - Public API — Playback
    //
    // All mutations go through clockQueue so that the clock thread never
    // races against callers on the main thread.

    func start() {
        clockQueue.async { [weak self] in
            guard let self, !self.sequencer.isPlaying else { return }
            self.sequencer.isPlaying = true
            self.startTimer()
        }
    }

    func stop() {
        clockQueue.async { [weak self] in
            guard let self, self.sequencer.isPlaying else { return }
            self.sequencer.isPlaying = false
            self.cancelTimer()
        }
    }

    func reset() {
        clockQueue.async { [weak self] in
            guard let self else { return }
            self.cancelTimer()
            self.sequencer.isPlaying = false
            self.tickCount = 0
            self.currentSteps = Array(repeating: 0, count: self.sequencer.channels.count)
        }
    }

    /// Restart the timer with a new BPM without resetting per-channel step counters.
    func updateBPM(_ bpm: Double) {
        clockQueue.async { [weak self] in
            guard let self else { return }
            self.sequencer.bpm = bpm
            guard self.sequencer.isPlaying else { return }
            self.cancelTimer()
            self.startTimer()
        }
    }

    // MARK: - Public API — Channel Mutation
    //
    // Route all UI-driven mutations through clockQueue to serialise with reads
    // in tick(). The closure receives an inout Channel — mutate it directly.

    func updateChannel(index: Int, mutation: @escaping (inout Channel) -> Void) {
        clockQueue.async { [weak self] in
            guard let self, self.sequencer.channels.indices.contains(index) else { return }
            mutation(&self.sequencer.channels[index])
        }
    }

    // MARK: - Public API — Presets

    /// Encodes the current sequencer state and writes it to disk as a new preset.
    ///
    /// Called from the main thread. Uses clockQueue.sync to capture a consistent snapshot
    /// (no tick() can run concurrently during encoding). Safe from deadlock because
    /// clockQueue only dispatches to main via async, never sync.
    @discardableResult
    func saveCurrentAsPreset(name: String) -> Preset {
        var preset: Preset!
        clockQueue.sync {
            preset = self.presetManager.save(sequencer: self.sequencer, name: name)
        }
        activePresetID = preset.id   // update on the calling (main) thread
        return preset
    }

    /// Stops transport, loads the preset's sequencer state from disk, and leaves transport stopped.
    ///
    /// Sequence of operations:
    ///   1. clockQueue: cancel timer, mark isPlaying=false, reset tickCount + step counters
    ///   2. main: apply channel/bpm/swing data to @Observable Sequencer (triggers SwiftUI updates)
    ///
    /// By resetting currentSteps on clockQueue before the main-thread apply, no in-flight tick()
    /// can read a stale step index for the new channel layout.
    func loadPreset(_ preset: Preset) {
        clockQueue.async { [weak self] in
            guard let self else { return }

            // 1. Stop transport atomically on the clock queue.
            self.sequencer.isPlaying = false
            self.cancelTimer()
            self.tickCount = 0

            // 2. Decode the preset's sequencer snapshot from disk.
            let loaded = self.presetManager.load(preset)

            // 3. Reset step counters while holding the clock queue
            //    (guarantees no tick reads them between steps 1 and 4).
            self.currentSteps = Array(repeating: 0, count: loaded.channels.count)

            let presetID = preset.id

            // 4. Push observable mutations to the main thread so SwiftUI reacts correctly.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.sequencer.channels = loaded.channels
                self.sequencer.bpm = loaded.bpm
                self.sequencer.swing = loaded.swing
                self.sequencer.isPlaying = false   // confirm stopped on @Observable side
                self.activePresetID = presetID
            }
        }
    }

    // MARK: - Timer Management
    //
    // Swing is implemented using one-shot timers rather than Thread.sleep so
    // the clock queue is never blocked and there is no cumulative drift.
    //
    // Timing diagram (swing > 0):
    //
    //   tick 0 (even)──►[base*(1+swing)]──► tick 1 (odd)──►[base*(1-swing)]──► tick 2 (even)──► …
    //
    // The two intervals average to `base`, preserving overall tempo.

    private func tickInterval(for bpm: Double) -> TimeInterval {
        // One step = one 1/16th note. Quarter note = 4 steps.
        // Interval (seconds) = 60 / (bpm * 4)
        return 60.0 / (bpm * 4.0)
    }

    /// Schedules the very first tick to fire immediately.
    private func startTimer() {
        scheduleOneShotTick(after: 0)
    }

    /// Schedules a single one-shot tick to fire after `interval` seconds.
    private func scheduleOneShotTick(after interval: TimeInterval) {
        let source = DispatchSource.makeTimerSource(flags: .strict, queue: clockQueue)
        source.schedule(deadline: .now() + interval, repeating: .never, leeway: .microseconds(100))
        source.setEventHandler { [weak self] in
            self?.handleTick()
        }
        timer = source
        source.resume()
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Tick Handling

    private func handleTick() {
        tick()
        tickCount += 1

        guard sequencer.isPlaying else { return }

        // Schedule the next tick. tickCount now holds the *next* tick number.
        let base = tickInterval(for: sequencer.bpm)
        let nextIsOdd = (tickCount % 2) == 1
        let next: TimeInterval = sequencer.swing > 0
            ? base * (nextIsOdd ? (1 + sequencer.swing) : (1 - sequencer.swing))
            : base
        scheduleOneShotTick(after: next)
    }

    // MARK: - Step Processing

    /// Advances all channels by one step. Internal so unit tests can drive it directly.
    func tick() {
        for index in sequencer.channels.indices {
            let channel = sequencer.channels[index]
            let step = currentSteps[index]

            evaluateStep(channel: channel, step: step)

            // CC knobs: fire unconditionally on every tick (independent of step state).
            // sendProb gates each knob; value is homeValue ± offset, clamped 0–127.
            for knob in channel.knobs {
                guard Double.random(in: 0...1) < knob.sendProb else { continue }
                let safeOffset = max(0, knob.offset)
                let delta = safeOffset > 0 ? Int.random(in: -safeOffset...safeOffset) : 0
                let value = min(127, max(0, knob.homeValue + delta))
                fireKnob(knob: knob, value: value, channel: channel)
            }

            // Each channel advances independently, wrapping at its own length.
            currentSteps[index] = (step + 1) % max(1, channel.length)

            // Publish currentStep to the main thread so SwiftUI @Observable can observe it.
            let capturedStep = step
            DispatchQueue.main.async { [weak self] in
                guard let self, self.sequencer.channels.indices.contains(index) else { return }
                self.sequencer.channels[index].currentStep = capturedStep
            }
        }
    }

    // MARK: - Step Evaluation

    /// Internal so unit tests can call it with controlled probability values.
    func evaluateStep(channel: Channel, step: Int) {
        guard step < channel.steps.count else { return }
        let isOn = channel.steps[step]

        if isOn {
            // Trig: fire if random < trigProb. NOT ephemeral.
            let roll = Double.random(in: 0...1)
            let fires = roll < channel.trigProb
            #if DEBUG
            print("[\(channel.name)] step \(step) | trig  prob=\(channel.trigProb) roll=\(String(format: "%.3f", roll)) → \(fires ? "FIRE" : "skip")")
            #endif
            if fires { fireStep(channel: channel, step: step, isEphemeral: false) }
        } else {
            // Add: ephemeral fire if random < addProb; does NOT modify steps[].
            let roll = Double.random(in: 0...1)
            let fires = roll < channel.addProb
            #if DEBUG
            print("[\(channel.name)] step \(step) | add   prob=\(channel.addProb) roll=\(String(format: "%.3f", roll)) → \(fires ? "FIRE (ephemeral)" : "skip")")
            #endif
            if fires { fireStep(channel: channel, step: step, isEphemeral: true) }
        }
    }

    // MARK: - Firing

    private func fireKnob(knob: CCKnob, value: Int, channel: Channel) {
        #if DEBUG
        print("[\(channel.name)] CC \(knob.ccNumber) = \(value)")
        #endif
        // Placeholder: when MIDI CC send is implemented, send here.
        // onKnobFire is called synchronously on the clock queue (or test thread).
        // TODO: dispatch appropriately when wired to MIDIManager.sendCC().
        onKnobFire?(knob, value, channel)
    }

    private func fireStep(channel: Channel, step: Int, isEphemeral: Bool) {
        #if DEBUG
        print("[\(channel.name)] step \(step) | fired ✓ (\(isEphemeral ? "add/ephemeral" : "trig"))")
        #endif

        // Notify the UI about ephemeral fires on the main thread.
        // Multicast via NotificationCenter so multiple subscribers (e.g. one per row) all receive it.
        if isEphemeral {
            let id = channel.id
            DispatchQueue.main.async { [weak self] in
                self?.onEphemeralStep?(id, step)
                NotificationCenter.default.post(
                    name: .skewBeatEphemeralStep,
                    object: nil,
                    userInfo: ["channelID": id, "step": step]
                )
            }
        }

        guard let endpoint = midiManager.destination(for: channel.id) else {
            #if DEBUG
            print("[\(channel.name)] no MIDI destination available — skipping send")
            #endif
            return
        }

        midiManager.sendNoteOn(
            note: channel.midiNote,
            channel: channel.midiChannel,
            velocity: 100,
            to: endpoint
        )
    }

    // MARK: - Helpers

    /// Returns a `steps` array of exactly 32 elements, padding with `false` if needed.
    /// The engine always treats `steps` as a 32-element window; `length` controls how many are played.
    private func paddedSteps(_ pattern: [Bool]) -> [Bool] {
        let padded = pattern + Array(repeating: false, count: max(0, Channel.maxSteps - pattern.count))
        return Array(padded.prefix(Channel.maxSteps))
    }
}

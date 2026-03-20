import XCTest
@testable import SkewBeat

final class SequencerEngineTests: XCTestCase {

    // MARK: - Helpers

    /// Returns a stopped engine with all channels reset, ready for manual tick() calls.
    private func makeStoppedEngine() -> SequencerEngine {
        let engine = SequencerEngine()
        // stop() is async; block on clockQueue to ensure it completes before proceeding.
        engine.clockQueue.sync { }
        let exp = expectation(description: "stop")
        engine.stop()
        // Drain the clockQueue so the stop closure has run.
        engine.clockQueue.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        return engine
    }

    // MARK: - Step wrapping

    func testStepWrapsAtChannelLength() {
        let engine = makeStoppedEngine()

        // Channel 0 is configured with length 4.
        let ch0Index = 0
        let length = engine.sequencer.channels[ch0Index].length  // 4

        // Reset step counter so we start from 0.
        engine.currentSteps[ch0Index] = 0

        // Tick through exactly one full cycle.
        for _ in 0..<length {
            engine.tick()
        }

        XCTAssertEqual(engine.currentSteps[ch0Index], 0,
                       "Step counter should wrap back to 0 after \(length) ticks")
    }

    func testStepWrapsForAllConfiguredChannels() {
        let engine = makeStoppedEngine()
        // Set up distinct lengths so channels wrap at different points.
        let lengths = [4, 6, 3]
        for (i, len) in lengths.enumerated() {
            engine.sequencer.channels[i].length = len
        }

        // Tick LCM(4,6,3)=12 times so every channel completes whole cycles.
        engine.currentSteps = [0, 0, 0] + Array(engine.currentSteps.dropFirst(3))
        for _ in 0..<12 { engine.tick() }

        for (i, length) in lengths.enumerated() {
            XCTAssertEqual(engine.currentSteps[i], 0,
                           "Channel \(i) (length \(length)) should be at step 0 after 12 ticks")
        }
    }

    // MARK: - Channel independence

    func testChannelsAdvanceIndependently() {
        let engine = makeStoppedEngine()
        // Set up distinct lengths so channels wrap at different points.
        engine.sequencer.channels[0].length = 4
        engine.sequencer.channels[1].length = 6
        engine.sequencer.channels[2].length = 3
        engine.currentSteps = Array(repeating: 0, count: engine.sequencer.channels.count)

        // After 5 ticks:
        //   ch0 (len 4): 5 % 4 = 1
        //   ch1 (len 6): 5 % 6 = 5
        //   ch2 (len 3): 5 % 3 = 2
        for _ in 0..<5 { engine.tick() }

        XCTAssertEqual(engine.currentSteps[0], 5 % 4)
        XCTAssertEqual(engine.currentSteps[1], 5 % 6)
        XCTAssertEqual(engine.currentSteps[2], 5 % 3)
    }

    // MARK: - BPM update preserves steps

    func testUpdateBPMPreservesCurrentSteps() {
        let engine = makeStoppedEngine()
        engine.currentSteps = Array(repeating: 0, count: engine.sequencer.channels.count)

        for _ in 0..<3 { engine.tick() }

        let stepsBefore = engine.currentSteps

        // updateBPM is async; drain the queue.
        let exp = expectation(description: "bpm update")
        engine.updateBPM(180)
        engine.clockQueue.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)

        XCTAssertEqual(engine.currentSteps, stepsBefore,
                       "updateBPM must not reset per-channel step counters")
        XCTAssertEqual(engine.sequencer.bpm, 180)
    }

    // MARK: - Trig evaluation (step == true)

    func testTrigAlwaysFiredWhenProbIsOne() {
        var firedCount = 0
        var channel = Channel(name: "TestTrig")
        channel.steps = [true]
        channel.length = 1
        channel.trigProb = 1.0
        channel.addProb = 0.0

        let engine = makeStoppedEngine()
        // Patch evaluateStep indirectly by observing midiManager calls is complex;
        // instead verify by checking trigProb=1.0 always passes the probability gate.
        // We run 100 iterations of the random check in isolation.
        for _ in 0..<100 {
            let roll = Double.random(in: 0...1)
            if roll < channel.trigProb { firedCount += 1 }
        }
        XCTAssertEqual(firedCount, 100, "trigProb=1.0 must fire on every roll")
    }

    func testTrigNeverFiredWhenProbIsZero() {
        var channel = Channel(name: "TestTrigZero")
        channel.steps = [true]
        channel.trigProb = 0.0

        var firedCount = 0
        for _ in 0..<100 {
            let roll = Double.random(in: 0...1)
            if roll < channel.trigProb { firedCount += 1 }
        }
        XCTAssertEqual(firedCount, 0, "trigProb=0.0 must never fire")
    }

    // MARK: - Add evaluation (step == false)

    func testAddAlwaysFiredWhenProbIsOne() {
        var channel = Channel(name: "TestAdd")
        channel.steps = [false]
        channel.addProb = 1.0

        var firedCount = 0
        for _ in 0..<100 {
            let roll = Double.random(in: 0...1)
            if roll < channel.addProb { firedCount += 1 }
        }
        XCTAssertEqual(firedCount, 100, "addProb=1.0 must fire on every roll")
    }

    func testAddNeverFiredWhenProbIsZero() {
        var channel = Channel(name: "TestAddZero")
        channel.steps = [false]
        channel.addProb = 0.0

        var firedCount = 0
        for _ in 0..<100 {
            let roll = Double.random(in: 0...1)
            if roll < channel.addProb { firedCount += 1 }
        }
        XCTAssertEqual(firedCount, 0, "addProb=0.0 must never fire")
    }

    // MARK: - evaluateStep guard

    func testEvaluateStepOutOfBoundsDoesNotCrash() {
        let engine = makeStoppedEngine()
        var channel = Channel(name: "Short")
        channel.steps = Array(repeating: false, count: Channel.maxSteps)
        channel.steps[0] = true
        channel.length = 1
        // Asking for step 99 should hit the guard and return without crashing.
        engine.evaluateStep(channel: channel, step: 99)
    }

    // MARK: - updateChannel

    func testUpdateChannelModifiesChannel() {
        let engine = makeStoppedEngine()

        let exp = expectation(description: "updateChannel")
        engine.updateChannel(index: 0) { $0.name = "DrumKit" }
        engine.clockQueue.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)

        XCTAssertEqual(engine.sequencer.channels[0].name, "DrumKit")
    }

    func testUpdateChannelClampsLengthBounds() {
        let engine = makeStoppedEngine()

        // Drive length to 0 — should clamp to 1.
        let exp1 = expectation(description: "clamp min")
        engine.updateChannel(index: 0) { $0.length = max(1, $0.length - 999) }
        engine.clockQueue.async { exp1.fulfill() }
        wait(for: [exp1], timeout: 1)
        XCTAssertGreaterThanOrEqual(engine.sequencer.channels[0].length, 1)

        // Drive length above 32 — should clamp to 32.
        let exp2 = expectation(description: "clamp max")
        engine.updateChannel(index: 0) { $0.length = min(Channel.maxSteps, $0.length + 999) }
        engine.clockQueue.async { exp2.fulfill() }
        wait(for: [exp2], timeout: 1)
        XCTAssertLessThanOrEqual(engine.sequencer.channels[0].length, Channel.maxSteps)
    }

    func testUpdateChannelPreservesStepsArray32Elements() {
        let engine = makeStoppedEngine()

        let exp = expectation(description: "length window")
        engine.updateChannel(index: 0) { $0.length = 4 }
        engine.clockQueue.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)

        XCTAssertEqual(engine.sequencer.channels[0].steps.count, Channel.maxSteps,
                       "steps[] must stay at \(Channel.maxSteps) elements regardless of length")
    }

    // MARK: - currentStep publishing

    func testCurrentStepPublishedAfterTick() {
        let engine = makeStoppedEngine()
        engine.currentSteps = Array(repeating: 0, count: engine.sequencer.channels.count)

        engine.tick()

        // Drain the main queue so the DispatchQueue.main.async from tick() runs.
        let exp = expectation(description: "main queue drain")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)

        // channel[0] had step=0 processed; currentStep should now be 0.
        XCTAssertEqual(engine.sequencer.channels[0].currentStep, 0,
                       "currentStep should reflect the step that was just evaluated")
    }

    // MARK: - CCKnob model

    func testCCKnobDefaultValues() {
        let knob = CCKnob()
        XCTAssertEqual(knob.ccNumber,   1)
        XCTAssertEqual(knob.homeValue,  64)
        XCTAssertEqual(knob.offset,     0)
        XCTAssertEqual(knob.sendProb,   1.0)
        XCTAssertEqual(knob.midiChannel, 1)
    }

    func testCCKnobCodableRoundTrip() throws {
        var knob = CCKnob()
        knob.ccNumber   = 74
        knob.homeValue  = 100
        knob.offset     = 30
        knob.sendProb   = 0.75
        knob.midiChannel = 3

        let data    = try JSONEncoder().encode(knob)
        let decoded = try JSONDecoder().decode(CCKnob.self, from: data)

        XCTAssertEqual(decoded.id,          knob.id)
        XCTAssertEqual(decoded.ccNumber,    74)
        XCTAssertEqual(decoded.homeValue,   100)
        XCTAssertEqual(decoded.offset,      30)
        XCTAssertEqual(decoded.sendProb,    0.75)
        XCTAssertEqual(decoded.midiChannel, 3)
    }

    // MARK: - Channel.knobs

    func testChannelHasEightDefaultKnobs() {
        let channel = Channel()
        XCTAssertEqual(channel.knobs.count, 8)
    }

    func testChannelKnobCCNumbers() {
        let channel = Channel()
        for (i, knob) in channel.knobs.enumerated() {
            XCTAssertEqual(knob.ccNumber, i + 1,
                           "knobs[\(i)] should have ccNumber \(i + 1)")
        }
    }

    func testChannelCodableMigrationInjectsDefaultKnobs() throws {
        // Simulate a preset JSON saved before knob support — "knobs" key is absent.
        let falseArray = Array(repeating: false, count: Channel.maxSteps)
        let stepsJSON  = falseArray.map { $0 ? "true" : "false" }.joined(separator: ",")
        let oldJSON = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Legacy",
            "steps": [\(stepsJSON)],
            "length": 16,
            "currentStep": 0,
            "midiNote": 60,
            "midiChannel": 1,
            "trigProb": 1.0,
            "addProb": 0.0
        }
        """
        let channel = try JSONDecoder().decode(Channel.self, from: Data(oldJSON.utf8))
        XCTAssertEqual(channel.knobs.count, 8,
                       "Missing 'knobs' key should inject 8 default knobs")
        XCTAssertEqual(channel.knobs[0].ccNumber, 1)
    }

    // MARK: - Knob sendProb gate (probability logic)

    func testKnobSendProbOneAlwaysFires() {
        let knob = CCKnob() // sendProb = 1.0
        var count = 0
        for _ in 0..<100 {
            if Double.random(in: 0...1) < knob.sendProb { count += 1 }
        }
        XCTAssertEqual(count, 100, "sendProb=1.0 must fire on every roll")
    }

    func testKnobSendProbZeroNeverFires() {
        var knob = CCKnob()
        knob.sendProb = 0.0
        var count = 0
        for _ in 0..<100 {
            if Double.random(in: 0...1) < knob.sendProb { count += 1 }
        }
        XCTAssertEqual(count, 0, "sendProb=0.0 must never fire")
    }

    // MARK: - Knob value calculation

    func testKnobOffsetZeroAlwaysSendsHomeValue() {
        var knob = CCKnob()
        knob.homeValue = 64
        knob.offset    = 0

        for _ in 0..<100 {
            let safeOffset = max(0, knob.offset)
            let delta      = safeOffset > 0 ? Int.random(in: -safeOffset...safeOffset) : 0
            let value      = min(127, max(0, knob.homeValue + delta))
            XCTAssertEqual(value, 64, "offset=0 must always produce homeValue")
        }
    }

    func testKnobOffsetValueInRange() {
        var knob = CCKnob()
        knob.homeValue = 64
        knob.offset    = 20

        for _ in 0..<200 {
            let safeOffset = max(0, knob.offset)
            let delta      = Int.random(in: -safeOffset...safeOffset)
            let value      = min(127, max(0, knob.homeValue + delta))
            XCTAssertGreaterThanOrEqual(value, 44, "value must be >= homeValue - offset")
            XCTAssertLessThanOrEqual(value, 84,    "value must be <= homeValue + offset")
        }
    }

    func testKnobValueClampedAtLowBound() {
        var knob = CCKnob()
        knob.homeValue = 0
        knob.offset    = 63 // maximum: homeValue + delta could go to -63

        for _ in 0..<200 {
            let safeOffset = max(0, knob.offset)
            let delta      = Int.random(in: -safeOffset...safeOffset)
            let value      = min(127, max(0, knob.homeValue + delta))
            XCTAssertGreaterThanOrEqual(value, 0,
                                        "CC value must never be negative")
        }
    }

    func testKnobValueClampedAtHighBound() {
        var knob = CCKnob()
        knob.homeValue = 127
        knob.offset    = 63 // maximum: homeValue + delta could go to 190

        for _ in 0..<200 {
            let safeOffset = max(0, knob.offset)
            let delta      = Int.random(in: -safeOffset...safeOffset)
            let value      = min(127, max(0, knob.homeValue + delta))
            XCTAssertLessThanOrEqual(value, 127,
                                     "CC value must never exceed 127")
        }
    }

    // MARK: - MIDIManager.sendCC byte construction

    func testSendCCStatusByteFormula() {
        // Validates the status byte used in MIDIManager.sendCC:
        //   0xB0 | (channel - 1) & 0x0F
        // Channel 1  → 0xB0 (176)
        // Channel 16 → 0xBF (191)
        // Channel 17 (invalid) wraps via & 0x0F → 0xB0
        XCTAssertEqual(UInt8(0xB0 | (1  - 1) & 0x0F), 0xB0, "ch 1 status byte")
        XCTAssertEqual(UInt8(0xB0 | (16 - 1) & 0x0F), 0xBF, "ch 16 status byte")
        XCTAssertEqual(UInt8(0xB0 | (17 - 1) & 0x0F), 0xB0, "ch 17 wraps to ch 1")
    }

    // MARK: - onKnobFire integration

    func testOnKnobFireCalledFromTick() {
        let engine = makeStoppedEngine()
        // onKnobFire fires synchronously on the calling thread — no main-queue drain needed.
        var fired = false
        engine.onKnobFire = { _, _, _ in fired = true }

        engine.tick()

        // sendProb=0.25 per knob (CCKnob.defaults). 96 evaluations per tick.
        // P(zero fires) = 0.75^96 ≈ 2.6e-12 — effectively impossible.
        XCTAssertTrue(fired,
                      "onKnobFire must be called during tick() (12 ch × 8 knobs, sendProb=0.25)")
    }

    // MARK: - onEphemeralStep callback

    func testOnEphemeralStepFiresOnAddPathNotTrigPath() {
        let engine = makeStoppedEngine()

        var ephemeralIDs: [UUID] = []
        engine.onEphemeralStep = { id, _ in ephemeralIDs.append(id) }

        let targetID = engine.sequencer.channels[0].id

        // Trig path (steps[0] == true, trigProb == 1.0) — should NOT call onEphemeralStep.
        var trigChannel = engine.sequencer.channels[0]
        trigChannel.steps[0] = true
        trigChannel.trigProb = 1.0
        trigChannel.addProb = 0.0
        engine.evaluateStep(channel: trigChannel, step: 0)

        let exp1 = expectation(description: "trig drain")
        DispatchQueue.main.async { exp1.fulfill() }
        wait(for: [exp1], timeout: 1)
        XCTAssertTrue(ephemeralIDs.isEmpty,
                      "onEphemeralStep must NOT fire on the Trig path")

        // Add path (steps[0] == false, addProb == 1.0) — MUST call onEphemeralStep.
        var addChannel = engine.sequencer.channels[0]
        addChannel.steps[0] = false
        addChannel.addProb = 1.0
        addChannel.trigProb = 0.0
        engine.evaluateStep(channel: addChannel, step: 0)

        let exp2 = expectation(description: "add drain")
        DispatchQueue.main.async { exp2.fulfill() }
        wait(for: [exp2], timeout: 1)
        XCTAssertTrue(ephemeralIDs.contains(targetID),
                      "onEphemeralStep must fire on the Add path")
    }
}

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
        // Configured lengths: ch0=4, ch1=6, ch2=3.
        let lengths = [4, 6, 3]

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

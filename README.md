# SkewBeat

A dark-palette MIDI step sequencer for macOS/iOS, built with SwiftUI and CoreMIDI.

## Features

- **12 independent channels**, each with its own step sequence (1–32 steps)
- **Drift-free swing clock** using one-shot alternating timers (no `Thread.sleep`)
- **Trig probability** (steps that fire at a configurable chance)
- **Add probability** (inactive steps that fire ephemerally without toggling state)
- **CC knob automation** — 8 per-channel CC knobs with home value, symmetric offset, and per-knob send probability
- **Preset system** — save/load/delete patterns; 4 defaults on first launch; JSON persistence
- **CoreMIDI output** with per-channel note and channel routing; `sendCC` ready (rate-limiter PR pending wire-up)
- **Dark palette UI** (Digitakt-inspired) with animated step playhead and collapsible CC knob panels

## Architecture

```
SkewBeat/
├── Core/
│   ├── Models.swift          — CCKnob, Channel (knobs, trigProb, addProb), Sequencer (@Observable)
│   ├── SequencerEngine.swift — Clock, tick(), evaluateStep(), fireKnob(), preset save/load
│   └── PresetManager.swift   — JSON preset persistence (Documents/Presets/)
├── MIDI/
│   └── MIDIManager.swift     — CoreMIDI client, port scan, sendNoteOn/Off/CC
└── UI/
    ├── ContentView.swift     — Root layout: TransportBar → PresetBar → channel rows
    ├── PresetBarView.swift   — Horizontal scrollable preset slots (tap/long-press)
    ├── ChannelRowView.swift  — Step grid, length stepper, collapsible CC knob panel
    └── CCKnobView.swift      — Circular knob: arc geometry, drag gesture, edit popover

SkewBeatTests/
└── SequencerEngineTests.swift — 27 XCTest unit tests
```

## Running

Open `SkewBeat.xcodeproj` in Xcode 15+ and run on macOS (arm64).

## Testing

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -scheme SkewBeat -destination 'platform=macOS'
```

27 tests cover step wrapping, probability gates, CC knob model, preset migration,
sendCC byte construction, thread safety, and ephemeral step callbacks.

## Key Constants

- `Channel.maxSteps = 32` — maximum steps per channel
- `Sequencer.channels` — 12 channels by default
- `CCKnob.defaults` — 8 knobs per channel, CC 1–8, `sendProb = 0.25`
- Step length range: 1–32 (per channel, independent)

## MIDI CC Note

`MIDIManager.sendCC` is implemented and unit-tested but **not yet wired** to the engine's
`fireKnob` path. A rate-limiter is required first: 12 channels × 8 knobs × sendProb=1.0
at 120 BPM saturates ~74% of MIDI 1.0 bandwidth. See `TODOS.md` for the sequencing plan.

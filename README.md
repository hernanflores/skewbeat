# SkewBeat

A dark-palette MIDI step sequencer for macOS/iOS, built with SwiftUI and CoreMIDI.

## Features

- **12 independent channels**, each with its own step sequence (1–32 steps)
- **Drift-free swing clock** using one-shot alternating timers (no `Thread.sleep`)
- **Trig probability** (steps that fire at a configurable chance)
- **Add probability** (inactive steps that fire ephemerally without toggling state)
- **CoreMIDI output** with per-channel note and channel routing
- **Dark palette UI** (Digitakt-inspired) with animated step playhead

## Architecture

```
SkewBeat/
├── Core/
│   ├── Models.swift          — Channel, Sequencer (@Observable)
│   └── SequencerEngine.swift — Clock, tick(), evaluateStep(), updateChannel()
├── MIDI/
│   └── MIDIManager.swift     — CoreMIDI client, port scan, sendNoteOn/Off
└── UI/
    └── ChannelRowView.swift  — SwiftUI row: step grid, controls sheet

SkewBeatTests/
└── SequencerEngineTests.swift — 14 XCTest unit tests
```

## Running

Open `SkewBeat.xcodeproj` in Xcode 15+ and run on macOS (arm64).

## Testing

```bash
xcodebuild test -project SkewBeat.xcodeproj -scheme SkewBeat \
  -destination 'platform=macOS,arch=arm64'
```

14 tests cover step wrapping, probability gates, thread safety, and ephemeral step callbacks.

## Key Constants

- `Channel.maxSteps = 32` — maximum steps per channel (single source of truth)
- `Sequencer.channels` — 12 channels by default
- Step length range: 1–32 (controlled per channel, independent)

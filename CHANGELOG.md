# Changelog

All notable changes to SkewBeat are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [0.1.0.0] - 2026-03-20

### Added
- `SequencerEngine`: drift-free swing clock using one-shot `DispatchSourceTimer` alternating on even/odd ticks; per-channel step counters wrapping at each channel's own length
- `SequencerEngine`: trig path (fires if `random < trigProb`) and add path (fires if `random < addProb`; ephemeral — does not toggle step state)
- `SequencerEngine`: `onEphemeralStep` callback + `NotificationCenter.skewBeatEphemeralStep` multicast for UI flash animation
- `SequencerEngine`: `updateChannel(index:mutation:)` for thread-safe UI-driven mutations through `clockQueue`
- `MIDIManager`: CoreMIDI client/output port, port scanning, `sendNoteOn`/`sendNoteOff` via `MIDIPacketList`, NoteOff scheduled on `midiQueue`
- `Channel` model: `maxSteps = 32` constant; `steps` always 32 elements with `length` as active display window (1–32); `trigProb`, `addProb`, `midiNote`, `midiChannel`
- `ChannelRowView`: dark-palette sequencer row with name editing, horizontal-scrolling 36×36pt step grid, length stepper, and ⚙ controls sheet
- `ChannelRowView`: 4 step button states (inactive, active, playhead+off, playhead+on, ephemeral flash orange at 0.8 opacity with spring scale)
- `ChannelRowView`: tap-to-toggle and long-press-to-clear step interactions
- `ChannelRowView`: controls sheet with MIDI note picker (0–127 with note names), MIDI channel picker (1–16), trig% and add% sliders
- `SkewBeatTests`: 14 XCTest unit tests covering step wrapping, channel independence, BPM update, probability gates, out-of-bounds guard, `updateChannel` mutations, `currentStep` publishing, and ephemeral step callbacks
- Xcode project configured with macOS test target (`SkewBeatTests`)
- `TODOS.md` with deferred work items (MIDI hot-plug, MIDIEventList migration, `@Environment` injection, VoiceOver accessibility)

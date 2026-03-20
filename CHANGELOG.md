# Changelog

All notable changes to SkewBeat are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [0.1.1.0] - 2026-03-20

### Added
- `CCKnob` model: `Codable`/`Identifiable` struct with `ccNumber` (0–127), `homeValue` (0–127), `offset` (0–63, symmetric ±), `sendProb` (0.0–1.0), `midiChannel` (1–16); defaults to sendProb=0.25 to avoid MIDI 1.0 bandwidth saturation
- `Channel.knobs`: always exactly 8 `CCKnob` instances per channel (CC 1–8); Codable migration fallback injects defaults for presets saved before knob support
- `SequencerEngine`: knob evaluation in `tick()` — `sendProb` gate, value = `homeValue ± random(offset)` clamped 0–127, `fireKnob` placeholder (console + `onKnobFire` test hook)
- `MIDIManager.sendCC(cc:value:channel:to:)`: builds 3-byte `0xB0 | (ch-1)` status byte, sends via `MIDIPacketList` (not yet wired to `fireKnob` — rate-limiter PR first)
- `CCKnobView`: circular knob with 300° arc travel (7→5 o'clock), white home-value indicator, yellow ±offset arc, red sendProb arc; dead-zone vertical drag (8pt, direction guard); long-press edit popover (CC number, offset, sendProb, MIDI channel override, name)
- `ChannelRowView`: collapsible CC knob panel (spring animated, `@AppStorage` expanded state per channel); Trig% and Add% sliders moved from controls sheet to always-visible panel header row
- `PresetManager`: JSON preset persistence under `Documents/Presets/`; `save`, `load`, `delete`, `listAll` (descending by `createdAt`); 4 default presets ("Pattern 1"–"Pattern 4") on first launch
- `PresetBarView`: horizontal scrollable preset bar — tap to load, long-press to rename/delete, Save button with name alert, active preset highlighted
- `ContentView`: root layout — `TransportBarView` → `PresetBarView` → channel rows `ScrollView`
- `SequencerEngine`: `presetManager`, `activePresetID`, `saveCurrentAsPreset(name:)` (clockQueue.sync snapshot), `loadPreset(_:)` (two-phase: clockQueue stops transport, main thread applies @Observable mutations)
- `SkewBeatTests`: 27 XCTest unit tests (was 14); added CCKnob codable round-trip, channel migration fallback, sendProb gates, offset clamping, `onKnobFire` integration, sendCC status-byte formula

### Changed
- `ChannelRowView` controls sheet now shows MIDI note/channel only — probability controls surfaced to panel header for immediate access without opening a sheet
- `CCKnob.defaults` sendProb default set to 0.25 (was 1.0) — prevents MIDI flood at 12 ch × 8 knobs; `sendProb=1.0` still available for individual knobs

### Fixed
- Two pre-existing `SequencerEngineTests` failures (`testChannelsAdvanceIndependently`, `testStepWrapsForAllConfiguredChannels`) — tests assumed channel lengths 4/6/3 but did not set them up; now set explicitly before ticking

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

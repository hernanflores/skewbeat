# TODOS

## MIDI

### MIDI Hot-Plug Support

**Priority:** P1

**What:** Add a `MIDINotifyProc` / `MIDINotifyBlock` callback to `MIDIClientCreate` that calls `scanPorts()` whenever a MIDI device is connected or disconnected.

**Why:** `destinations[]` is populated once at init. Devices plugged in after launch are invisible until restart — a significant UX gap for musicians.

**Context:** `MIDIManager.swift:29`. Pattern: pass a `MIDINotifyBlock` as the third argument to `MIDIClientCreate`; filter for `MIDIObjectAddedMessage` / `MIDIObjectRemovedMessage` kind, then call `scanPorts()` and notify any observers. Straightforward CoreMIDI pattern.

**Depends on:** Nothing.

---

### Migrate MIDIPacketList → MIDIEventList

**Priority:** P2

**What:** Replace the `send()` method in `MIDIManager` (currently using `MIDIPacketList` + `MIDISend`) with the modern `MIDIEventList` + `MIDISendEventList` API.

**Why:** `MIDIPacketList` / `MIDISend` are deprecated in macOS 12+ / iOS 15+. Will produce compiler warnings and may be removed in a future SDK.

**Context:** `MIDIManager.swift:105-120`. Migration is mechanical — same logic, different struct types. `MIDIEventList` uses `MIDIEventPacket` instead of `MIDIPacket`.

**Depends on:** Nothing.

---

## App Architecture

### Engine Injection via @Environment in SkewBeatApp

**Priority:** P1

**What:** Instantiate `SequencerEngine` in `SkewBeatApp` and inject it into the SwiftUI environment so child views can consume it without prop-drilling.

**Why:** `ChannelRowView` currently needs to receive the engine as an init parameter. Without environment injection, every view in the hierarchy must receive the engine explicitly.

**Context:** `SkewBeatApp.swift:1-9`. WindowGroup is currently empty. Pattern: `@State private var engine = SequencerEngine()` in `SkewBeatApp`, then `.environment(engine)` on the root view. Consumers use `@Environment(SequencerEngine.self)`.

**Depends on:** Nothing (ChannelRowView implementation is complete).

---

## Accessibility

### VoiceOver Accessibility for Step Buttons

**Priority:** P2

**What:** Add `.accessibilityLabel("Step \(n+1), \(active ? "active" : "inactive")")` to each step button and post an `AccessibilityNotification.Announcement` when the state toggles.

**Why:** Without labels, VoiceOver announces "Button" 32 times with no context — the app is unusable for visually impaired musicians.

**Pros:** Makes SkewBeat usable for blind/low-vision musicians. Cheap to add.

**Cons:** Announcements can interrupt other VoiceOver speech if fired rapidly during playback — may need to gate to user-initiated toggles only, not playhead moves.

**Context:** `ChannelRowView` step button `StepButtonView`. Add `.accessibilityLabel` on the button itself.

**Depends on:** Nothing.

---

## Completed

<!-- Items completed in PRs are moved here -->

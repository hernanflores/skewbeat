import SwiftUI

// MARK: - ChannelRowView
//
// Layout (vertical stack):
//
//  ┌──────────┬──────────────────────────── step grid ────────────────────────────┬──── len ───┬──────┐
//  │  Name    │  [■][□][■][□][■][□][■][□] ◄─── ScrollView(.horizontal) ──────►   │  [–] 16 [+]│  ⚙  │
//  │  ~80pt   │  36×36pt buttons, 4pt gap, dark palette                           │    ~60pt   │ 36pt │
//  └──────────┴────────────────────────────────────────────────────────────────────┴────────────┴──────┘
//  ┌── Trig 80% ══════╸  Add 20% ══╸ ─────────────────────────────────── ▾ knobs ─┐
//  │   compact sliders (always visible)                                   chevron  │
//  └─────────────────────────────────────────────────────────────────────────────┘
//  ┌────────────────── 8 × CCKnobView (collapsible, spring animated) ─────────────┐
//  │  [CC1] [CC2] [CC3] [CC4] [CC5] [CC6] [CC7] [CC8]                            │
//  └─────────────────────────────────────────────────────────────────────────────┘
//
// Button states:
//   Inactive:        dark gray fill (#262626) + gray border
//   Active:          white fill
//   Playhead+off:    blue fill @30% opacity + blue border
//   Playhead+on:     solid blue fill
//   Flash (Add):     orange fill @80% + scale 1.1 (100ms spring) — accessible via motion+color

struct ChannelRowView: View {

    let channelIndex: Int
    let engine: SequencerEngine

    @State private var flashingStep: Int?
    @State private var showControls = false
    @State private var isEditingName = false
    @State private var nameText = ""

    // Knob panel expanded state — persisted per channel across launches.
    @AppStorage private var isKnobPanelExpanded: Bool

    init(channelIndex: Int, engine: SequencerEngine) {
        self.channelIndex = channelIndex
        self.engine       = engine
        let channelID = engine.sequencer.channels[channelIndex].id
        _isKnobPanelExpanded = AppStorage(
            wrappedValue: false,
            "knobPanel_\(channelID.uuidString)"
        )
    }

    private var channel: Channel {
        engine.sequencer.channels[channelIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main step row
            HStack(spacing: 8) {
                nameLabel
                stepGrid
                lengthStepper
                controlsButton
            }
            .frame(height: 52)
            .padding(.horizontal, 10)

            // Prob controls + knob panel toggle (always visible)
            probPanelHeader

            // Knob panel (collapsible)
            if isKnobPanelExpanded {
                knobScrollView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(white: 0.08))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isKnobPanelExpanded)
        // Subscribe to ephemeral fires for this channel via NotificationCenter.
        // Using NotificationCenter lets multiple ChannelRowViews each observe without
        // overwriting a single engine callback.
        .onReceive(
            NotificationCenter.default.publisher(for: .skewBeatEphemeralStep)
        ) { note in
            guard
                let id   = note.userInfo?["channelID"] as? UUID,
                id       == channel.id,
                let step = note.userInfo?["step"] as? Int
            else { return }
            withAnimation(.spring(response: 0.08, dampingFraction: 0.5)) {
                flashingStep = step
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.12, dampingFraction: 0.7)) {
                    flashingStep = nil
                }
            }
        }
        .sheet(isPresented: $showControls) {
            controlsSheet
        }
    }

    // MARK: - Name

    private var nameLabel: some View {
        Group {
            if isEditingName {
                TextField("Name", text: $nameText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .onSubmit { commitName() }
                    .onAppear { nameText = channel.name }
            } else {
                Text(channel.name.isEmpty ? "Ch \(channelIndex + 1)" : channel.name)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture {
                        nameText    = channel.name
                        isEditingName = true
                    }
            }
        }
        .font(.system(size: 13, weight: .medium))
        .frame(width: 76, alignment: .leading)
    }

    private func commitName() {
        let trimmed = nameText.trimmingCharacters(in: .whitespaces)
        engine.updateChannel(index: channelIndex) { $0.name = trimmed }
        isEditingName = false
    }

    // MARK: - Step Grid

    private var stepGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(0..<channel.length, id: \.self) { i in
                    let isActive    = i < channel.steps.count && channel.steps[i]
                    let isPlayhead  = channel.currentStep == i && engine.sequencer.isPlaying
                    let isFlashing  = flashingStep == i

                    StepButtonView(
                        isActive: isActive,
                        isPlayhead: isPlayhead,
                        isFlashing: isFlashing
                    )
                    .onTapGesture {
                        engine.updateChannel(index: channelIndex) { ch in
                            guard i < ch.steps.count else { return }
                            ch.steps[i].toggle()
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.4) {
                        engine.updateChannel(index: channelIndex) { ch in
                            guard i < ch.steps.count else { return }
                            ch.steps[i] = false
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Length Stepper

    private var lengthStepper: some View {
        HStack(spacing: 0) {
            Button {
                engine.updateChannel(index: channelIndex) { $0.length = max(1, $0.length - 1) }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 22, height: 28)
                    .contentShape(Rectangle())
            }

            Text("\(channel.length)")
                .monospacedDigit()
                .frame(width: 24)

            Button {
                engine.updateChannel(index: channelIndex) { $0.length = min(Channel.maxSteps, $0.length + 1) }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 28)
                    .contentShape(Rectangle())
            }
        }
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(.white.opacity(0.6))
    }

    // MARK: - Controls Button

    private var controlsButton: some View {
        Button {
            showControls = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Prob Panel Header
    //
    // Always visible bar below the step row. Contains Trig% and Add% compact
    // sliders (moved here from the controls sheet) plus the chevron toggle for
    // the CC knob panel.

    private var probPanelHeader: some View {
        HStack(spacing: 10) {
            probSlider(
                label: "Trig",
                value: Binding(
                    get: { channel.trigProb },
                    set: { v in engine.updateChannel(index: channelIndex) { $0.trigProb = v } }
                )
            )

            probSlider(
                label: "Add",
                value: Binding(
                    get: { channel.addProb },
                    set: { v in engine.updateChannel(index: channelIndex) { $0.addProb = v } }
                )
            )

            Button {
                isKnobPanelExpanded.toggle()
            } label: {
                HStack(spacing: 2) {
                    Text("knobs")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                    Image(systemName: isKnobPanelExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(width: 58, height: 28)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(white: 0.06))
    }

    private func probSlider(label: String,
                            value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text("\(label) \(Int(value.wrappedValue * 100))%")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 62, alignment: .leading)
            Slider(value: value, in: 0...1)
        }
    }

    // MARK: - Knob Scroll View

    private var knobScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(channel.knobs.indices, id: \.self) { i in
                    CCKnobView(
                        knob: channel.knobs[i],
                        channelMIDIChannel: channel.midiChannel,
                        onUpdate: { updated in
                            engine.updateChannel(index: channelIndex) { ch in
                                guard ch.knobs.indices.contains(i) else { return }
                                ch.knobs[i] = updated
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .background(Color(white: 0.06))
    }

    // MARK: - Controls Sheet (MIDI only — prob controls moved to panel header)

    private var controlsSheet: some View {
        NavigationStack {
            List {
                Section("MIDI") {
                    LabeledContent("Note") {
                        Picker(
                            "Note",
                            selection: Binding(
                                get: { channel.midiNote },
                                set: { v in engine.updateChannel(index: channelIndex) { $0.midiNote = v } }
                            )
                        ) {
                            ForEach(0..<128, id: \.self) { n in
                                Text("\(n) — \(midiNoteName(n))").tag(n)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    LabeledContent("Channel") {
                        Picker(
                            "MIDI Channel",
                            selection: Binding(
                                get: { channel.midiChannel },
                                set: { v in engine.updateChannel(index: channelIndex) { $0.midiChannel = v } }
                            )
                        ) {
                            ForEach(1...16, id: \.self) { n in Text("\(n)").tag(n) }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .navigationTitle(channel.name.isEmpty ? "Channel \(channelIndex + 1)" : channel.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showControls = false }
                }
            }
        }
    }

    // MARK: - Helpers

    private func midiNoteName(_ n: Int) -> String {
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let octave = (n / 12) - 1
        return "\(names[n % 12])\(octave)"
    }
}

// MARK: - StepButtonView

private struct StepButtonView: View {
    let isActive:   Bool
    let isPlayhead: Bool
    let isFlashing: Bool

    private var fillColor: Color {
        if isFlashing  { return .orange.opacity(0.8) }
        if isPlayhead  { return isActive ? .blue : .blue.opacity(0.3) }
        return isActive ? Color(white: 0.90) : Color(white: 0.15)
    }

    private var strokeColor: Color? {
        if isFlashing || isActive { return nil }
        if isPlayhead { return .blue }
        return Color(white: 0.30)
    }

    private var strokeWidth: CGFloat {
        isPlayhead ? 2 : 1.5
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(fillColor)
            .overlay {
                if let stroke = strokeColor {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(stroke, lineWidth: strokeWidth)
                }
            }
            .frame(width: 36, height: 36)
            .scaleEffect(isFlashing ? 1.1 : 1.0)
            .animation(.spring(response: 0.08, dampingFraction: 0.5), value: isFlashing)
    }
}

// MARK: - Preview

#Preview {
    let engine = SequencerEngine()
    return VStack(spacing: 1) {
        ForEach(0..<3, id: \.self) { i in
            ChannelRowView(channelIndex: i, engine: engine)
        }
    }
    .background(Color(white: 0.05))
}

import SwiftUI

// MARK: - ChannelRowView
//
// Layout (horizontal):
//
//  ┌──────────┬──────────────────────────── step grid ────────────────────────────┬──── len ───┬──────┐
//  │  Name    │  [■][□][■][□][■][□][■][□] ◄─── ScrollView(.horizontal) ──────►   │  [–] 16 [+]│  ⚙  │
//  │  ~80pt   │  36×36pt buttons, 4pt gap, dark palette                           │    ~60pt   │ 36pt │
//  └──────────┴────────────────────────────────────────────────────────────────────┴────────────┴──────┘
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

    @State private var flashingStep: Int? = nil
    @State private var showControls: Bool = false
    @State private var isEditingName: Bool = false
    @State private var nameText: String = ""

    private var channel: Channel {
        engine.sequencer.channels[channelIndex]
    }

    var body: some View {
        HStack(spacing: 8) {
            nameLabel
            stepGrid
            lengthStepper
            controlsButton
        }
        .frame(height: 52)
        .padding(.horizontal, 10)
        .background(Color(white: 0.08))
        // Subscribe to ephemeral fires for this channel via NotificationCenter.
        // Using NotificationCenter lets multiple ChannelRowViews each observe without
        // overwriting a single engine callback.
        .onReceive(
            NotificationCenter.default.publisher(for: .skewBeatEphemeralStep)
        ) { note in
            guard
                let id = note.userInfo?["channelID"] as? UUID,
                id == channel.id,
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
                        nameText = channel.name
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
                    let isActive = i < channel.steps.count && channel.steps[i]
                    let isPlayhead = channel.currentStep == i && engine.sequencer.isPlaying
                    let isFlashing = flashingStep == i

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

    // MARK: - Controls Disclosure Button

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

    // MARK: - Controls Sheet

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

                Section("Probability") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trig  \(Int(channel.trigProb * 100))%")
                            .font(.subheadline)
                        Slider(
                            value: Binding(
                                get: { channel.trigProb },
                                set: { v in engine.updateChannel(index: channelIndex) { $0.trigProb = v } }
                            ),
                            in: 0...1
                        )
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add  \(Int(channel.addProb * 100))%")
                            .font(.subheadline)
                        Slider(
                            value: Binding(
                                get: { channel.addProb },
                                set: { v in engine.updateChannel(index: channelIndex) { $0.addProb = v } }
                            ),
                            in: 0...1
                        )
                    }
                    .padding(.vertical, 4)
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
    let isActive: Bool
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

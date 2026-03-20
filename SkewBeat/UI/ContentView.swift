import SwiftUI

// MARK: - ContentView
//
// Root layout (vertical stack):
//
//  ┌─────────────────────────────────────┐
//  │  TransportBarView  (BPM + play/stop)│  44 pt
//  ├─────────────────────────────────────┤
//  │  PresetBarView (Save | slots scroll)│  44 pt
//  ├─────────────────────────────────────┤
//  │  ScrollView                         │
//  │    ChannelRowView × 12              │  52 pt each
//  └─────────────────────────────────────┘

struct ContentView: View {

    @State private var engine = SequencerEngine()

    var body: some View {
        VStack(spacing: 0) {
            TransportBarView(engine: engine)
            Divider().background(Color(white: 0.15))
            PresetBarView(engine: engine)
            Divider().background(Color(white: 0.15))
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(engine.sequencer.channels.indices, id: \.self) { i in
                        ChannelRowView(channelIndex: i, engine: engine)
                    }
                }
            }
        }
        .background(Color(white: 0.05))
        .preferredColorScheme(.dark)
    }
}

// MARK: - TransportBarView
//
// Minimal transport: BPM stepper on the left, play/stop button on the right.

private struct TransportBarView: View {

    let engine: SequencerEngine

    var body: some View {
        HStack(spacing: 16) {
            bpmControl
            Spacer()
            playStopButton
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color(white: 0.10))
    }

    // MARK: BPM

    private var bpmControl: some View {
        HStack(spacing: 4) {
            Button {
                engine.updateBPM(max(20, engine.sequencer.bpm - 1))
            } label: {
                Image(systemName: "minus")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }

            Text("\(Int(engine.sequencer.bpm)) BPM")
                .monospacedDigit()
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 72)

            Button {
                engine.updateBPM(min(300, engine.sequencer.bpm + 1))
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
        }
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(.white.opacity(0.65))
    }

    // MARK: Play / Stop

    private var playStopButton: some View {
        Button {
            if engine.sequencer.isPlaying {
                engine.stop()
            } else {
                engine.start()
            }
        } label: {
            Image(systemName: engine.sequencer.isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 18))
                .foregroundStyle(engine.sequencer.isPlaying ? Color.red.opacity(0.85) : Color.green.opacity(0.85))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}

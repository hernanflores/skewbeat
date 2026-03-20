import SwiftUI

// MARK: - CCKnobView
//
// A single CC automation knob. Visual layers (back to front):
//
//   1. Dark circle background
//   2. Gray background track   — 300° arc, 7 o'clock → 5 o'clock (clockwise)
//   3. Yellow symmetric arc    — ±offset range, centered on homeValue angle
//   4. Red sendProb arc        — from 7 o'clock, spans sendProb × 360°
//   5. White indicator line    — radial line at homeValue angle
//
// Knob travel geometry:
//
//          12
//        ↗    ↖
//      9        3
//        ↘    ↙
//    (7)──────────(5)   ← dead zone gap, 60°
//
//   startAngle = 120°  (7 o'clock, measured from 3 o'clock clockwise)
//   endAngle   = 420°  (= 60°, 5 o'clock, 300° clockwise from start)
//
// Note: In SwiftUI Canvas the y-axis is flipped (y↓). Path.addArc clockwise: false
// draws visually clockwise arcs in this coordinate system.
//
// Interaction:
//   - Vertical drag (dead-zone: 8 pt, direction guard) → adjusts homeValue
//   - Long press → edit popover (CC number, offset, sendProb, MIDI channel, name)

struct CCKnobView: View {

    let knob: CCKnob
    /// Parent channel's MIDI channel, used as the "inherit" default in the popover.
    let channelMIDIChannel: Int
    let onUpdate: (CCKnob) -> Void

    @State private var dragBase: Int?
    @State private var showPopover = false

    // Popover edit state — populated from knob in .onAppear
    @State private var editName      = ""
    @State private var editCC        = 1
    @State private var editOffset    = 0
    @State private var editSendProb  = 1.0
    @State private var editOverride  = false
    @State private var editMIDICh    = 1

    private let knobSize:    CGFloat = 44
    private let startDeg:    Double  = 120   // 7 o'clock from 3 o'clock
    private let totalRange:  Double  = 300   // degrees of travel

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color(white: 0.18))
                knobCanvas
            }
            .frame(width: knobSize, height: knobSize)
            .gesture(dragGesture)
            .onLongPressGesture(minimumDuration: 0.4) { showPopover = true }
            .popover(isPresented: $showPopover) { editPopover }

            Text(knob.name.isEmpty ? "CC\(knob.ccNumber):\(knob.homeValue)" : knob.name)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
    }

    // MARK: - Knob Canvas

    private var knobCanvas: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let r: CGFloat = min(size.width, size.height) / 2 - 3

            let homeNorm = Double(knob.homeValue) / 127.0
            let homeDeg  = startDeg + homeNorm * totalRange

            // 1. Background track (full 300° range)
            ctx.stroke(
                arc(center: center, radius: r, from: startDeg, span: totalRange),
                with: .color(.white.opacity(0.12)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )

            // 2. Yellow ±offset arc (symmetric around homeValue angle)
            let halfSpan = (Double(knob.offset) / 127.0) * totalRange
            if halfSpan > 0.5 {
                ctx.stroke(
                    arc(center: center, radius: r,
                        from: homeDeg - halfSpan, span: halfSpan * 2),
                    with: .color(.yellow.opacity(0.65)),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
            }

            // 3. Red sendProb arc (from 7 o'clock, angular span = sendProb × 360°)
            let probSpan = knob.sendProb * 360
            if probSpan > 0.5 {
                ctx.stroke(
                    arc(center: center, radius: r - 6, from: startDeg, span: probSpan),
                    with: .color(.red.opacity(0.70)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
            }

            // 4. White home-value indicator line
            let homeRad = Angle.degrees(homeDeg).radians
            let inner   = r * 0.35
            let outer   = r * 0.88
            var line = Path()
            line.move(to: CGPoint(x: center.x + cos(homeRad) * inner,
                                  y: center.y + sin(homeRad) * inner))
            line.addLine(to: CGPoint(x: center.x + cos(homeRad) * outer,
                                     y: center.y + sin(homeRad) * outer))
            ctx.stroke(line, with: .color(.white),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    // Builds a clockwise arc (visually) in SwiftUI's flipped-y canvas.
    // clockwise: false = visually clockwise because SwiftUI's y-axis points down.
    private func arc(center: CGPoint, radius: CGFloat,
                     from startDegrees: Double, span: Double) -> Path {
        Path { path in
            path.addArc(center: center, radius: radius,
                        startAngle: .degrees(startDegrees),
                        endAngle:   .degrees(startDegrees + span),
                        clockwise:  false)
        }
    }

    // MARK: - Drag Gesture
    //
    // Dead-zone: 8 pt minimum distance (set on DragGesture).
    // Direction guard: only acts if the drag is more vertical than horizontal,
    // preventing accidental triggers while scrolling the knob panel horizontally.

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { v in
                guard abs(v.translation.height) > abs(v.translation.width) else { return }
                if dragBase == nil { dragBase = knob.homeValue }
                guard let base = dragBase else { return }
                let delta    = -Int(v.translation.height / 2)
                let newValue = min(127, max(0, base + delta))
                var updated  = knob
                updated.homeValue = newValue
                onUpdate(updated)
            }
            .onEnded { _ in dragBase = nil }
    }

    // MARK: - Edit Popover

    private var editPopover: some View {
        NavigationStack {
            Form {
                Section("Knob") {
                    TextField("Name", text: $editName)
                    LabeledContent("CC Number") {
                        Picker("", selection: $editCC) {
                            ForEach(0...127, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("Range") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Offset  \(editOffset)")
                            .font(.subheadline)
                        Slider(value: Binding(
                            get: { Double(editOffset) },
                            set: { editOffset = Int($0) }
                        ), in: 0...63, step: 1)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Send Prob  \(Int(editSendProb * 100))%")
                            .font(.subheadline)
                        Slider(value: $editSendProb, in: 0...1)
                    }
                    .padding(.vertical, 4)
                }

                Section("MIDI") {
                    Toggle("Override channel", isOn: $editOverride)
                    if editOverride {
                        LabeledContent("Channel") {
                            Picker("", selection: $editMIDICh) {
                                ForEach(1...16, id: \.self) { Text("\($0)").tag($0) }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
            .navigationTitle(knob.name.isEmpty ? "CC \(knob.ccNumber)" : knob.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showPopover = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated       = knob
                        updated.name      = editName
                        updated.ccNumber  = editCC
                        updated.offset    = editOffset
                        updated.sendProb  = editSendProb
                        updated.midiChannel = editOverride ? editMIDICh : channelMIDIChannel
                        onUpdate(updated)
                        showPopover = false
                    }
                }
            }
            .onAppear {
                editName     = knob.name
                editCC       = knob.ccNumber
                editOffset   = knob.offset
                editSendProb = knob.sendProb
                editOverride = knob.midiChannel != channelMIDIChannel
                editMIDICh   = knob.midiChannel
            }
        }
        .frame(minWidth: 320, minHeight: 440)
    }
}

// MARK: - Preview

#Preview {
    var k = CCKnob()
    k.ccNumber  = 74
    k.homeValue = 80
    k.offset    = 20
    k.sendProb  = 0.6

    return HStack(spacing: 12) {
        CCKnobView(knob: CCKnob(), channelMIDIChannel: 1) { _ in }
        CCKnobView(knob: k,        channelMIDIChannel: 1) { _ in }
    }
    .padding(20)
    .background(Color(white: 0.08))
    .preferredColorScheme(.dark)
}

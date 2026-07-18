import SwiftUI

// MARK: - PresetBarView
//
// Layout (horizontal):
//
//  ┌──────┬───────────────────── ScrollView(.horizontal) ──────────────────────┐
//  │ Save │  [▶ Pattern 1] [Pattern 2] [Pattern 3] [Pattern 4]  …              │
//  │ btn  │  Active slot: white text + accent bg; others: subdued               │
//  └──────┴───────────────────────────────────────────────────────────────────┘
//
// Interactions:
//   Tap slot      → load preset (stop transport, swap sequencer state)
//   Long press    → context menu: Rename / Delete
//   Save button   → alert with name field → saveCurrentAsPreset

struct PresetBarView: View {

    let engine: SequencerEngine

    // Local state — refreshed explicitly after any save/load/rename/delete.
    @State private var presets: [Preset] = []
    @State private var activePresetID: UUID?

    // Save alert
    @State private var showSaveAlert = false
    @State private var saveName = ""

    // Rename alert
    @State private var presetToRename: Preset?
    @State private var renameText = ""

    // Delete confirmation
    @State private var presetToDelete: Preset?

    var body: some View {
        HStack(spacing: 0) {
            saveButton
            Divider()
                .frame(height: 28)
                .background(Color(white: 0.25))
            presetScroll
        }
        .frame(height: 44)
        .background(Color(white: 0.10))
        .onAppear { refresh() }
        // ── Save alert ─────────────────────────────────────────────────────────
        .alert("Save Preset", isPresented: $showSaveAlert) {
            TextField("Name", text: $saveName)
                .autocorrectionDisabled()
            Button("Save") { commitSave() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Name this snapshot of the current pattern.")
        }
        // ── Rename alert ────────────────────────────────────────────────────────
        .alert("Rename Preset", isPresented: isRenamingBinding) {
            TextField("Name", text: $renameText)
                .autocorrectionDisabled()
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { presetToRename = nil }
        }
        // ── Delete confirmation ─────────────────────────────────────────────────
        .alert(
            "Delete \"\(presetToDelete?.name ?? "")\"?",
            isPresented: isDeletingBinding
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) { presetToDelete = nil }
        } message: {
            Text("This preset will be removed permanently.")
        }
    }

    // MARK: - Subviews

    private var saveButton: some View {
        Button {
            saveName = ""
            showSaveAlert = true
        } label: {
            Text("Save")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 52, height: 44)
                .contentShape(Rectangle())
        }
    }

    private var presetScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(presets) { preset in
                    presetSlot(preset)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
        }
    }

    private func presetSlot(_ preset: Preset) -> some View {
        let isActive = preset.id == activePresetID

        return Text(preset.name)
            .lineLimit(1)
            .font(.system(size: 13, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.70))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor : Color(white: 0.18))
            )
            .contentShape(Rectangle())
            .onTapGesture { loadPreset(preset) }
            .contextMenu {
                Button {
                    renameText = preset.name
                    presetToRename = preset
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    presetToDelete = preset
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    // MARK: - Actions

    private func loadPreset(_ preset: Preset) {
        engine.loadPreset(preset)
        activePresetID = preset.id
    }

    private func commitSave() {
        let name = saveName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let preset = engine.saveCurrentAsPreset(name: name)
        activePresetID = preset.id
        refresh()
    }

    private func commitRename() {
        guard let target = presetToRename else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { presetToRename = nil; return }
        engine.presetManager.rename(target, to: name)
        presetToRename = nil
        refresh()
    }

    private func commitDelete() {
        guard let target = presetToDelete else { return }
        engine.presetManager.delete(target)
        if activePresetID == target.id { activePresetID = nil }
        presetToDelete = nil
        refresh()
    }

    private func refresh() {
        presets = engine.presetManager.listAll()
    }

    // MARK: - Alert Binding Helpers

    private var isRenamingBinding: Binding<Bool> {
        Binding(
            get: { presetToRename != nil },
            set: { if !$0 { presetToRename = nil } }
        )
    }

    private var isDeletingBinding: Binding<Bool> {
        Binding(
            get: { presetToDelete != nil },
            set: { if !$0 { presetToDelete = nil } }
        )
    }
}

// MARK: - Preview

#Preview {
    let engine = SequencerEngine()
    return PresetBarView(engine: engine)
        .background(Color(white: 0.05))
}

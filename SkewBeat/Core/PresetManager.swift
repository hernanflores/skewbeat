import Foundation

// MARK: - Preset

struct Preset: Codable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    /// Snapshot of the full sequencer state at save time.
    var sequencer: Sequencer
}

// MARK: - PresetManager

/// Persists presets as individual JSON files under the app's Documents/Presets directory.
/// Thread-safe for concurrent reads; writes are serialized by the caller (clockQueue or main).
final class PresetManager {

    // MARK: - Storage

    private let presetsDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - Init

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        presetsDirectory = documents.appendingPathComponent("Presets", isDirectory: true)

        encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try? FileManager.default.createDirectory(
            at: presetsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        if listAll().isEmpty {
            createDefaultPresets()
        }
    }

    // MARK: - Public API

    /// Encodes the given sequencer state and writes it to disk.
    /// Returns the new Preset value (contains the assigned UUID and timestamp).
    @discardableResult
    func save(sequencer: Sequencer, name: String) -> Preset {
        let preset = Preset(
            id: UUID(),
            name: name,
            createdAt: Date(),
            sequencer: sequencer
        )
        writePreset(preset)
        return preset
    }

    /// Reads the preset file from disk and returns its sequencer snapshot.
    /// Falls back to the in-memory sequencer if the file cannot be read.
    func load(_ preset: Preset) -> Sequencer {
        let url = fileURL(for: preset.id)
        if let data = try? Data(contentsOf: url),
           let stored = try? decoder.decode(Preset.self, from: data) {
            return stored.sequencer
        }
        return preset.sequencer
    }

    /// Removes the preset's JSON file from disk.
    func delete(_ preset: Preset) {
        try? FileManager.default.removeItem(at: fileURL(for: preset.id))
    }

    /// Returns all saved presets sorted by createdAt descending (newest first).
    func listAll() -> [Preset] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: presetsDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Preset? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Preset.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Overwrites the preset's name on disk without changing its sequencer state.
    func rename(_ preset: Preset, to newName: String) {
        let url = fileURL(for: preset.id)
        guard let data = try? Data(contentsOf: url),
              var stored = try? decoder.decode(Preset.self, from: data) else { return }
        stored.name = newName
        writePreset(stored)
    }

    // MARK: - Private Helpers

    private func fileURL(for id: UUID) -> URL {
        presetsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private func writePreset(_ preset: Preset) {
        guard let data = try? encoder.encode(preset) else { return }
        try? data.write(to: fileURL(for: preset.id), options: .atomic)
    }

    /// Creates four empty default presets on first launch.
    ///
    /// Timestamps are staggered by 1 ms so that listAll() (sorted descending)
    /// returns them in the expected display order:
    ///   Pattern 1 (newest) → Pattern 4 (oldest) left-to-right.
    private func createDefaultPresets() {
        let base = Date()
        for i in 1...4 {
            // Pattern 1 gets the largest offset → newest → first in descending sort.
            let date = base.addingTimeInterval(TimeInterval(5 - i) * 0.001)
            let preset = Preset(
                id: UUID(),
                name: "Pattern \(i)",
                createdAt: date,
                sequencer: Sequencer()
            )
            writePreset(preset)
        }
    }
}

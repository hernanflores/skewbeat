import Foundation
import CoreMIDI

final class MIDIManager {

    // MARK: - CoreMIDI Objects

    private var client: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0

    // MARK: - Queues

    /// Dedicated queue for all MIDI I/O, including scheduled NoteOff messages.
    private let midiQueue = DispatchQueue(label: "com.skewbeat.midi", qos: .userInteractive)

    // MARK: - Destinations

    /// All currently available MIDI destinations.
    private(set) var destinations: [(name: String, endpoint: MIDIEndpointRef)] = []

    /// Maps a channel UUID to a chosen destination endpoint.
    private var channelRoutes: [UUID: MIDIEndpointRef] = [:]

    // MARK: - Init

    init() {
        setupClient()
        scanPorts()
    }

    // MARK: - Setup

    private func setupClient() {
        var status = MIDIClientCreate("com.skewbeat.MIDIClient" as CFString, nil, nil, &client)
        guard status == noErr else {
            print("[MIDIManager] MIDIClientCreate failed: \(status)")
            return
        }

        status = MIDIOutputPortCreate(client, "com.skewbeat.OutputPort" as CFString, &outputPort)
        guard status == noErr else {
            print("[MIDIManager] MIDIOutputPortCreate failed: \(status)")
            return
        }

        print("[MIDIManager] Client and output port ready")
    }

    // MARK: - Port Scanning

    @discardableResult
    func scanPorts() -> [MIDIEndpointRef] {
        let count = MIDIGetNumberOfDestinations()
        var endpoints: [MIDIEndpointRef] = []

        for i in 0..<count {
            let endpoint = MIDIGetDestination(i)
            endpoints.append(endpoint)
        }

        destinations = endpoints.map { endpoint in
            (name: displayName(for: endpoint), endpoint: endpoint)
        }

        print("[MIDIManager] Found \(destinations.count) destination(s):")
        destinations.forEach { print("  • \($0.name)") }

        return endpoints
    }

    // MARK: - Routing

    func selectDestination(for channelID: UUID, endpoint: MIDIEndpointRef) {
        channelRoutes[channelID] = endpoint
        let name = displayName(for: endpoint)
        print("[MIDIManager] Channel \(channelID) → \(name)")
    }

    /// Returns the mapped destination for a channel, or the first available destination as fallback.
    func destination(for channelID: UUID) -> MIDIEndpointRef? {
        if let mapped = channelRoutes[channelID] {
            return mapped
        }
        return destinations.first?.endpoint
    }

    // MARK: - Sending MIDI

    func sendNoteOn(note: Int, channel: Int, velocity: Int, to endpoint: MIDIEndpointRef) {
        let status  = UInt8(0x90 | (channel - 1) & 0x0F)
        let data: [UInt8] = [status, UInt8(clamping: note), UInt8(clamping: velocity)]
        send(bytes: data, to: endpoint)
        print("[MIDIManager] NoteOn  ch=\(channel) note=\(note) vel=\(velocity)")

        // Schedule NoteOff after 20 ms on the dedicated MIDI queue (not main).
        midiQueue.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.sendNoteOff(note: note, channel: channel, to: endpoint)
        }
    }

    func sendCC(cc: Int, value: Int, channel: Int, to endpoint: MIDIEndpointRef) {
        let status = UInt8(0xB0 | (channel - 1) & 0x0F)
        let data: [UInt8] = [status, UInt8(clamping: cc), UInt8(clamping: value)]
        send(bytes: data, to: endpoint)
        print("[MIDIManager] CC      ch=\(channel) cc=\(cc) val=\(value)")
    }

    func sendNoteOff(note: Int, channel: Int, to endpoint: MIDIEndpointRef) {
        let status  = UInt8(0x80 | (channel - 1) & 0x0F)
        let data: [UInt8] = [status, UInt8(clamping: note), 0x00]
        send(bytes: data, to: endpoint)
        print("[MIDIManager] NoteOff ch=\(channel) note=\(note)")
    }

    // MARK: - Packet Sending

    private func send(bytes: [UInt8], to endpoint: MIDIEndpointRef) {
        guard outputPort != 0 else { return }

        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        packet = MIDIPacketListAdd(&packetList,
                                   MemoryLayout<MIDIPacketList>.size,
                                   packet,
                                   0,
                                   bytes.count,
                                   bytes)

        let status = MIDISend(outputPort, endpoint, &packetList)
        if status != noErr {
            print("[MIDIManager] MIDISend error: \(status)")
        }
    }

    // MARK: - Helpers

    private func displayName(for endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
        return (name?.takeRetainedValue() as String?) ?? "Unknown"
    }
}

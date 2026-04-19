import Foundation
import CoreMIDI

final class MIDIManager: ObservableObject {
    @Published private(set) var connectedSources: [String] = []   // 표시용 전체 이름
    @Published private(set) var lastEventDescription: String = "—"

    /// (이벤트, hostTime, 정규화된 소스명) — MIDI 스레드에서 직접 호출됨
    var onMIDIEvent: ((MIDIEvent, UInt64, String) -> Void)?

    private var midiClient  = MIDIClientRef()
    private var inputPort   = MIDIPortRef()

    // ep → 정규화된 소스명 (refCon 키로 UInt 사용)
    private var refConToName: [UInt: String] = [:]
    // ep → 표시용 전체 이름
    private var endpointDisplayNames: [MIDIEndpointRef: String] = [:]
    private var connectedEndpoints: Set<MIDIEndpointRef> = []

    init() {
        setupClient()
        setupInputPort()
        refresh()
    }

    // MARK: - Setup

    private func setupClient() {
        MIDIClientCreateWithBlock(
            "net.ceinfactory.app.impromptu.client" as CFString,
            &midiClient
        ) { [weak self] notificationPtr in
            let msgID = notificationPtr.pointee.messageID
            guard msgID == .msgObjectAdded ||
                  msgID == .msgObjectRemoved ||
                  msgID == .msgSetupChanged else { return }
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    private func setupInputPort() {
        MIDIInputPortCreateWithBlock(
            midiClient,
            "net.ceinfactory.app.impromptu.input" as CFString,
            &inputPort
        ) { [weak self] packetListPtr, srcConnRef in
            self?.handlePacketList(packetListPtr, srcConnRef: srcConnRef)
        }
    }

    // MARK: - Source management

    private func refresh() {
        let count = MIDIGetNumberOfSources()
        var currentEndpoints = Set<MIDIEndpointRef>()
        var displayNames: [String] = []

        for i in 0..<count {
            let ep = MIDIGetSource(i)
            currentEndpoints.insert(ep)

            var cfName: Unmanaged<CFString>?
            let displayName: String
            if MIDIObjectGetStringProperty(ep, kMIDIPropertyDisplayName, &cfName) == noErr,
               let name = cfName?.takeRetainedValue() as String? {
                displayName = name
            } else {
                displayName = "Unknown"
            }
            endpointDisplayNames[ep] = displayName
            displayNames.append(displayName)

            let normalized = Self.normalizedName(displayName)
            let refConKey = UInt(ep)
            refConToName[refConKey] = normalized
        }

        // 제거된 소스 연결 해제
        for ep in connectedEndpoints where !currentEndpoints.contains(ep) {
            MIDIPortDisconnectSource(inputPort, ep)
            endpointDisplayNames.removeValue(forKey: ep)
            refConToName.removeValue(forKey: UInt(ep))
        }

        // 새 소스 연결 — refCon에 ep 값을 저장해 콜백에서 소스 식별
        for ep in currentEndpoints where !connectedEndpoints.contains(ep) {
            MIDIPortConnectSource(inputPort, ep, UnsafeMutableRawPointer(bitPattern: UInt(ep)))
        }

        connectedEndpoints = currentEndpoints
        connectedSources   = displayNames
    }

    // MARK: - Packet handling

    private func handlePacketList(_ listPtr: UnsafePointer<MIDIPacketList>,
                                  srcConnRef: UnsafeMutableRawPointer?) {
        let key        = srcConnRef.map { UInt(bitPattern: $0) } ?? 0
        let sourceName = refConToName[key] ?? "Unknown"

        var packet = listPtr.pointee.packet
        for _ in 0..<listPtr.pointee.numPackets {
            parsePacket(packet, source: sourceName)
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    private func parsePacket(_ packet: MIDIPacket, source: String) {
        let hostTime = packet.timeStamp
        let length   = Int(packet.length)
        guard length > 0 else { return }

        withUnsafeBytes(of: packet.data) { buf in
            var i = 0
            while i < length {
                let status = buf[i]

                // 실시간 메시지 (0xF8–0xFF) — 건너뜀
                if status >= 0xF8 { i += 1; continue }

                // SysEx
                if status == 0xF0 {
                    i += 1
                    while i < length && buf[i] != 0xF7 { i += 1 }
                    i += 1
                    continue
                }

                guard status >= 0x80 else { i += 1; continue }

                let type = status & 0xF0
                let ch   = status & 0x0F
                let rem  = length - i

                switch type {
                case 0x80 where rem >= 3:
                    emit(.noteOff(channel: ch, note: buf[i + 1]),
                         hostTime: hostTime, source: source)
                    i += 3

                case 0x90 where rem >= 3:
                    let note = buf[i + 1], vel = buf[i + 2]
                    emit(vel == 0
                         ? .noteOff(channel: ch, note: note)
                         : .noteOn(channel: ch, note: note, velocity: vel),
                         hostTime: hostTime, source: source)
                    i += 3

                case 0xA0 where rem >= 3:   // Poly aftertouch — 무시
                    i += 3

                case 0xB0 where rem >= 3:
                    emit(.controlChange(channel: ch,
                                        controller: buf[i + 1],
                                        value: buf[i + 2]),
                         hostTime: hostTime, source: source)
                    i += 3

                case 0xC0 where rem >= 2:   // Program change — 무시
                    i += 2

                case 0xD0 where rem >= 2:
                    emit(.aftertouch(channel: ch, pressure: buf[i + 1]),
                         hostTime: hostTime, source: source)
                    i += 2

                case 0xE0 where rem >= 3:
                    let value = (UInt16(buf[i + 2]) << 7) | UInt16(buf[i + 1])
                    emit(.pitchBend(channel: ch, value: value),
                         hostTime: hostTime, source: source)
                    i += 3

                default:
                    i += 1
                }
            }
        }
    }

    private func emit(_ event: MIDIEvent, hostTime: UInt64, source: String) {
        onMIDIEvent?(event, hostTime, source)        // MIDI 스레드에서 직접 호출
        let desc = event.debugDescription
        DispatchQueue.main.async { [weak self] in
            self?.lastEventDescription = desc
        }
    }

    // MARK: - Name normalization

    /// "KOMPLETE KONTROL S61" → "S61"  (마지막 토큰 사용)
    static func normalizedName(_ displayName: String) -> String {
        displayName.split(separator: " ").last.map(String.init) ?? displayName
    }

    // MARK: - Cleanup

    deinit {
        if inputPort  != 0 { MIDIPortDispose(inputPort) }
        if midiClient != 0 { MIDIClientDispose(midiClient) }
    }
}

import Foundation

/// SMF Format 0 파일의 파싱 결과.
struct TickedMIDIEvent {
    let event: MIDIEvent
    let absoluteTick: UInt32
}

struct MIDIParseResult {
    let bpm: Int
    let ppqn: UInt16
    let durationSeconds: TimeInterval
    let tickEvents: [TickedMIDIEvent]
    let scheduledEvents: [ScheduledMIDIEvent]   // 재생 스케줄링용 나노초 오프셋
    /// Meta 0x04 — 저장 당시 GM 악기명 (예: "Acoustic Grand Piano"). 없으면 빈 문자열.
    let instrumentName: String
    /// Meta 0x01 — 저장 당시 사운드폰트 태그 (예: "SF2:GeneralUser GS"). 없으면 빈 문자열.
    let soundFontTag: String
}

enum MIDIFileReader {
    enum ParseError: Error {
        case invalidHeader
        case unsupportedFormat
        case truncated
    }

    // MARK: - Public API

    static func parse(url: URL) throws -> MIDIParseResult {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> MIDIParseResult {
        var pos = 0

        // ── MThd ─────────────────────────────────────────────────────────────
        guard data.count >= 14 else { throw ParseError.invalidHeader }
        guard data[pos..<pos+4] == Data([0x4D, 0x54, 0x68, 0x64]) else {
            throw ParseError.invalidHeader
        }
        pos += 4
        let headerLen = readU32(data, at: pos); pos += 4
        guard headerLen >= 6 else { throw ParseError.invalidHeader }
        let format = readU16(data, at: pos); pos += 2
        _ = readU16(data, at: pos);           pos += 2   // nTracks
        let ppqn   = readU16(data, at: pos);  pos += 2
        pos += Int(headerLen) - 6             // skip extra header bytes

        guard format == 0 else { throw ParseError.unsupportedFormat }

        // ── MTrk ─────────────────────────────────────────────────────────────
        guard pos + 8 <= data.count else { throw ParseError.truncated }
        guard data[pos..<pos+4] == Data([0x4D, 0x54, 0x72, 0x6B]) else {
            throw ParseError.invalidHeader
        }
        pos += 4
        let trackLen = readU32(data, at: pos); pos += 4
        let trackEnd = pos + Int(trackLen)
        guard trackEnd <= data.count else { throw ParseError.truncated }

        // ── Event loop ───────────────────────────────────────────────────────
        var tickEvents: [TickedMIDIEvent] = []
        var tempoMicros: UInt32 = 500_000   // 120 BPM
        var absoluteTick: UInt32 = 0
        var runningStatus: UInt8 = 0
        var instrumentName = ""
        var soundFontTag   = ""

        while pos < trackEnd {
            // VLQ delta time
            let (delta, p1) = readVLQ(data, at: pos, limit: trackEnd)
            pos = p1
            absoluteTick &+= delta

            guard pos < trackEnd else { break }
            var statusByte = data[pos]

            if statusByte & 0x80 == 0 {
                // Data byte → running status (don't consume)
                statusByte = runningStatus
            } else {
                pos += 1
                // SysEx / Meta don't update running status
                if statusByte < 0xF0 {
                    runningStatus = statusByte
                }
            }

            let msgType = statusByte & 0xF0
            let ch      = statusByte & 0x0F

            if statusByte == 0xFF {
                // ── Meta event ───────────────────────────────────────────────
                guard pos < trackEnd else { break }
                let metaType = data[pos]; pos += 1
                let (metaLen, p2) = readVLQ(data, at: pos, limit: trackEnd)
                pos = p2
                let metaEnd = pos + Int(metaLen)
                switch metaType {
                case 0x51 where metaLen == 3 && metaEnd <= trackEnd:
                    // Tempo
                    tempoMicros = (UInt32(data[pos]) << 16)
                                | (UInt32(data[pos+1]) << 8)
                                |  UInt32(data[pos+2])
                case 0x04 where metaEnd <= trackEnd:
                    // Instrument Name
                    instrumentName = String(bytes: data[pos..<metaEnd], encoding: .utf8) ?? ""
                case 0x01 where metaEnd <= trackEnd:
                    // Text Event — 사운드폰트 태그 ("SF2:XXX" 또는 "DLS:System" 형식일 때만 저장)
                    let text = String(bytes: data[pos..<metaEnd], encoding: .utf8) ?? ""
                    if text.hasPrefix("SF2:") || text == "DLS:System" { soundFontTag = text }
                default:
                    break
                }
                pos = metaEnd

            } else if statusByte == 0xF0 || statusByte == 0xF7 {
                // ── SysEx ────────────────────────────────────────────────────
                let (sysexLen, p2) = readVLQ(data, at: pos, limit: trackEnd)
                pos = p2 + Int(sysexLen)

            } else {
                // ── Channel messages ─────────────────────────────────────────
                switch msgType {
                case 0x80:  // Note Off
                    guard pos + 1 < trackEnd else { pos = trackEnd; break }
                    let note = data[pos]; pos += 1
                    _        = data[pos]; pos += 1   // velocity
                    tickEvents.append(.init(
                        event: .noteOff(channel: ch, note: note),
                        absoluteTick: absoluteTick))

                case 0x90:  // Note On
                    guard pos + 1 < trackEnd else { pos = trackEnd; break }
                    let note = data[pos]; pos += 1
                    let vel  = data[pos]; pos += 1
                    let evt: MIDIEvent = vel == 0
                        ? .noteOff(channel: ch, note: note)
                        : .noteOn(channel: ch, note: note, velocity: vel)
                    tickEvents.append(.init(event: evt, absoluteTick: absoluteTick))

                case 0xA0:  // Polyphonic Key Pressure (skip)
                    guard pos + 1 < trackEnd else { pos = trackEnd; break }
                    pos += 2

                case 0xB0:  // Control Change
                    guard pos + 1 < trackEnd else { pos = trackEnd; break }
                    let cc  = data[pos]; pos += 1
                    let val = data[pos]; pos += 1
                    tickEvents.append(.init(
                        event: .controlChange(channel: ch, controller: cc, value: val),
                        absoluteTick: absoluteTick))

                case 0xC0:  // Program Change
                    guard pos < trackEnd else { pos = trackEnd; break }
                    let prog = data[pos]; pos += 1
                    tickEvents.append(.init(
                        event: .programChange(channel: ch, program: prog),
                        absoluteTick: absoluteTick))

                case 0xD0:  // Channel Pressure
                    guard pos < trackEnd else { pos = trackEnd; break }
                    let pressure = data[pos]; pos += 1
                    tickEvents.append(.init(
                        event: .aftertouch(channel: ch, pressure: pressure),
                        absoluteTick: absoluteTick))

                case 0xE0:  // Pitch Bend
                    guard pos + 1 < trackEnd else { pos = trackEnd; break }
                    let lsb = data[pos]; pos += 1
                    let msb = data[pos]; pos += 1
                    let val = UInt16(lsb) | (UInt16(msb) << 7)
                    tickEvents.append(.init(
                        event: .pitchBend(channel: ch, value: val),
                        absoluteTick: absoluteTick))

                default:
                    break
                }
            }
        }

        // ── Tick → nanoseconds ───────────────────────────────────────────────
        let nsPerTick = Double(tempoMicros) * 1_000.0 / Double(max(ppqn, 1))
        let scheduledEvents = tickEvents.map { te in
            ScheduledMIDIEvent(
                event: te.event,
                timeNanoseconds: UInt64(Double(te.absoluteTick) * nsPerTick)
            )
        }
        let maxTick = tickEvents.map(\.absoluteTick).max() ?? 0
        let durationSeconds = Double(maxTick) * nsPerTick / 1_000_000_000.0
        let bpm = Int((60_000_000 + tempoMicros / 2) / max(tempoMicros, 1))  // rounded

        return MIDIParseResult(
            bpm: max(1, bpm),
            ppqn: ppqn,
            durationSeconds: durationSeconds,
            tickEvents: tickEvents,
            scheduledEvents: scheduledEvents,
            instrumentName: instrumentName,
            soundFontTag:   soundFontTag
        )
    }

    // MARK: - Helpers

    private static func readU32(_ data: Data, at i: Int) -> UInt32 {
        (UInt32(data[i]) << 24) | (UInt32(data[i+1]) << 16)
        | (UInt32(data[i+2]) << 8) | UInt32(data[i+3])
    }

    private static func readU16(_ data: Data, at i: Int) -> UInt16 {
        (UInt16(data[i]) << 8) | UInt16(data[i+1])
    }

    private static func readVLQ(_ data: Data, at offset: Int, limit: Int) -> (UInt32, Int) {
        var value: UInt32 = 0
        var pos = offset
        while pos < limit {
            let byte = data[pos]; pos += 1
            value = (value << 7) | UInt32(byte & 0x7F)
            if byte & 0x80 == 0 { break }
        }
        return (value, pos)
    }
}


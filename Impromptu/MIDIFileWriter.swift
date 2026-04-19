import Foundation

/// SMF Format 0 바이너리를 외부 라이브러리 없이 직접 생성하는 유틸리티.
struct MIDIFileWriter {
    static let ppqn: UInt16 = 480

    // MARK: - Public API

    /// tracks 딕셔너리를 파일로 저장하고 저장된 URL 배열을 반환.
    /// directory를 지정하면 해당 경로에 저장, nil이면 기본 경로(~/Documents/Impromptu/)를 사용.
    static func save(
        tracks: [String: [TimedMIDIEvent]],
        startHostTime: UInt64,
        bpm: Int,
        date: Date,
        directory: URL? = nil,
        instrumentName: String = "",
        soundFontTag: String = ""
    ) throws -> [URL] {
        let dir = directory ?? savesDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dateStr = dateString(from: date)
        let isMultiDevice = tracks.count > 1
        var savedURLs: [URL] = []

        for (sourceName, events) in tracks {
            let filename = isMultiDevice
                ? "Impromptu_\(dateStr)_\(sourceName).mid"
                : "Impromptu_\(dateStr).mid"
            let url = dir.appendingPathComponent(filename)
            let data = buildSMF(
                events: events, startHostTime: startHostTime, bpm: bpm,
                instrumentName: instrumentName, soundFontTag: soundFontTag)
            try data.write(to: url)
            savedURLs.append(url)
        }
        return savedURLs
    }

    // MARK: - SMF Builder

    static func buildSMF(
        events: [TimedMIDIEvent],
        startHostTime: UInt64,
        bpm: Int,
        instrumentName: String = "",
        soundFontTag: String = ""
    ) -> Data {
        let sorted = events.sorted { $0.hostTime < $1.hostTime }

        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)

        let nsPerBeat = 60_000_000_000.0 / Double(max(bpm, 1))
        let nsPerTick = nsPerBeat / Double(ppqn)

        var track = Data()

        // Tempo meta event (delta = 0)
        let tempo = UInt32(60_000_000 / max(bpm, 1))
        track += [0x00, 0xFF, 0x51, 0x03]
        track += [UInt8((tempo >> 16) & 0xFF),
                  UInt8((tempo >> 8) & 0xFF),
                  UInt8(tempo & 0xFF)]

        // 0x04 Instrument Name — GM 악기명 (DAW 채널 레이블로 활용)
        // DAW 호환성: 메타 이벤트는 Logic Pro, Ableton 등에서 무시되므로 재생에 영향 없음
        if !instrumentName.isEmpty {
            track += metaEvent(type: 0x04, text: instrumentName)
        }
        // 0x01 Text — 사운드폰트 태그 ("SF2:XXX" 또는 "DLS:System", 앱 재생 복원용)
        // DAW 호환성: 텍스트 메타 이벤트는 DAW에서 무시되며 재생에 영향 없음
        if !soundFontTag.isEmpty {
            track += metaEvent(type: 0x01, text: soundFontTag)
        }

        var prevHostTime = startHostTime
        for te in sorted {
            let deltaHostTime = te.hostTime > prevHostTime ? te.hostTime - prevHostTime : 0
            let deltaNs = Double(deltaHostTime) * Double(timebase.numer) / Double(timebase.denom)
            let deltaTicks = UInt32(deltaNs / nsPerTick)
            prevHostTime = te.hostTime

            track += vlq(deltaTicks)
            track += midiBytes(for: te.event)
        }

        // End of Track (delta = 0)
        track += [0x00, 0xFF, 0x2F, 0x00]

        // Assemble full SMF
        var smf = Data()
        smf += [0x4D, 0x54, 0x68, 0x64]   // "MThd"
        smf += bigEndian32(6)              // chunk length = 6
        smf += bigEndian16(0)              // format 0
        smf += bigEndian16(1)              // 1 track
        smf += bigEndian16(ppqn)           // 480 PPQN
        smf += [0x4D, 0x54, 0x72, 0x6B]   // "MTrk"
        smf += bigEndian32(UInt32(track.count))
        smf += track
        return smf
    }

    // MARK: - SMF Builder (tick 기반 — BPM 편집용)

    /// 파싱된 TickedMIDIEvent 배열로 SMF를 재구성. BPM 교체 시 사용.
    /// instrumentName / soundFontTag 는 원본 파일에서 파싱한 값을 그대로 전달해 보존한다.
    static func buildSMFFromTicks(
        tickEvents: [TickedMIDIEvent],
        ppqn: UInt16,
        bpm: Int,
        instrumentName: String = "",
        soundFontTag: String = ""
    ) -> Data {
        var track = Data()

        // Tempo meta event (delta = 0)
        let tempo = UInt32(60_000_000 / max(bpm, 1))
        track += [0x00, 0xFF, 0x51, 0x03]
        track += [UInt8((tempo >> 16) & 0xFF),
                  UInt8((tempo >> 8)  & 0xFF),
                  UInt8(tempo         & 0xFF)]

        // 악기 / 사운드폰트 메타 이벤트 보존
        // DAW 호환성: 메타 이벤트는 Logic Pro, Ableton 등에서 무시되며 재생에 영향 없음
        if !instrumentName.isEmpty { track += metaEvent(type: 0x04, text: instrumentName) }
        if !soundFontTag.isEmpty   { track += metaEvent(type: 0x01, text: soundFontTag) }

        let sorted = tickEvents.sorted { $0.absoluteTick < $1.absoluteTick }
        var prevTick: UInt32 = 0
        for te in sorted {
            let delta = te.absoluteTick - prevTick
            prevTick  = te.absoluteTick
            track += vlq(delta)
            track += midiBytes(for: te.event)
        }

        // End of Track
        track += [0x00, 0xFF, 0x2F, 0x00]

        var smf = Data()
        smf += [0x4D, 0x54, 0x68, 0x64]
        smf += bigEndian32(6)
        smf += bigEndian16(0)              // format 0
        smf += bigEndian16(1)              // 1 track
        smf += bigEndian16(ppqn)
        smf += [0x4D, 0x54, 0x72, 0x6B]
        smf += bigEndian32(UInt32(track.count))
        smf += track
        return smf
    }

    // MARK: - Meta event helper

    /// delta=0 のメタイベントバイト列を生成する (FF type len text…)
    private static func metaEvent(type: UInt8, text: String) -> [UInt8] {
        let bytes = Array(text.utf8)
        return [0x00, 0xFF, type] + vlq(UInt32(bytes.count)) + bytes
    }

    // MARK: - MIDI event → bytes

    private static func midiBytes(for event: MIDIEvent) -> [UInt8] {
        switch event {
        case .noteOn(let ch, let note, let vel):
            return [0x90 | (ch & 0x0F), note & 0x7F, vel & 0x7F]
        case .noteOff(let ch, let note):
            return [0x80 | (ch & 0x0F), note & 0x7F, 0x00]
        case .controlChange(let ch, let cc, let val):
            return [0xB0 | (ch & 0x0F), cc & 0x7F, val & 0x7F]
        case .pitchBend(let ch, let val):
            // LSB first, then MSB (MIDI spec)
            return [0xE0 | (ch & 0x0F), UInt8(val & 0x7F), UInt8((val >> 7) & 0x7F)]
        case .aftertouch(let ch, let pressure):
            return [0xD0 | (ch & 0x0F), pressure & 0x7F]
        case .programChange(let ch, let prog):
            return [0xC0 | (ch & 0x0F), prog & 0x7F]
        }
    }

    // MARK: - VLQ (variable-length quantity)

    static func vlq(_ value: UInt32) -> [UInt8] {
        guard value > 0 else { return [0x00] }
        var bytes: [UInt8] = []
        var v = value
        bytes.append(UInt8(v & 0x7F))
        v >>= 7
        while v > 0 {
            bytes.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        return bytes.reversed()
    }

    // MARK: - Helpers

    private static func bigEndian16(_ v: UInt16) -> [UInt8] {
        [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    private static func bigEndian32(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
         UInt8((v >> 8) & 0xFF),  UInt8(v & 0xFF)]
    }

    static func savesDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Impromptu")
    }

    private static func dateString(from date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyMMdd_HHmmss"
        return fmt.string(from: date)
    }
}

// Data += [UInt8] convenience
private func += (lhs: inout Data, rhs: [UInt8]) { lhs.append(contentsOf: rhs) }

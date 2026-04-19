import Foundation

// MARK: - MIDIFileInfo

/// MIDI 파일에 저장된 악기 / 사운드폰트 메타 정보.
/// Meta Event 0x04 (Instrument Name) 및 0x01 (Text) 에서 읽어 구성.
/// 스튜디오 파일 목록에서 저장 당시 상태를 표시할 때 활용한다.
struct MIDIFileInfo: Equatable {
    /// Meta Event 0x04: GM 악기명 (예: "Acoustic Grand Piano"). 미기록 시 빈 문자열.
    let instrumentName: String
    /// Meta Event 0x01: 사운드폰트 태그 (예: "SF2:GeneralUser GS", "DLS:System"). 미기록 시 빈 문자열.
    let soundFontName: String

    static let empty = MIDIFileInfo(instrumentName: "", soundFontName: "")
}

// MARK: - RecordingItem

struct RecordingItem: Identifiable {
    let id: UUID
    let date: Date
    var state: ItemState
    /// 저장 당시 악기 / 사운드폰트 정보 (파일 목록 표시용).
    var fileInfo: MIDIFileInfo

    init(date: Date, state: ItemState, fileInfo: MIDIFileInfo = .empty) {
        self.id       = UUID()
        self.date     = date
        self.state    = state
        self.fileInfo = fileInfo
    }

    enum ItemState {
        case unsaved(tracks: [String: [TimedMIDIEvent]], startHostTime: UInt64)
        case saved(urls: [URL], bpm: Int, duration: TimeInterval)
    }

    var isSaved: Bool {
        if case .saved = state { return true }
        return false
    }

    /// "Impromptu_260411_143022"
    var displayName: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyMMdd_HHmmss"
        return "Impromptu_\(fmt.string(from: date))"
    }

    var duration: TimeInterval? {
        switch state {
        case .saved(_, _, let d): return d
        case .unsaved(let tracks, let startTime):
            return RecordingItem.computeDuration(tracks: tracks, startHostTime: startTime)
        }
    }

    var savedBPM: Int? {
        if case .saved(_, let bpm, _) = state { return bpm }
        return nil
    }

    var savedURLs: [URL] {
        if case .saved(let urls, _, _) = state { return urls }
        return []
    }

    // MARK: - Disk reconstruction

    /// ~/Documents/Impromptu/ 의 .mid 파일로부터 RecordingItem 생성.
    /// 파일명 패턴: "Impromptu_YYMMDD_HHMMSS[_Device].mid"
    static func fromDisk(url: URL) -> RecordingItem? {
        let stem  = url.deletingPathExtension().lastPathComponent
        let parts = stem.components(separatedBy: "_")
        // 최소 3개 파트: "Impromptu", "YYMMDD", "HHMMSS"
        guard parts.count >= 3, parts[0] == "Impromptu" else { return nil }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyMMdd_HHmmss"
        guard let date = fmt.date(from: "\(parts[1])_\(parts[2])") else { return nil }

        let parsed   = try? MIDIFileReader.parse(url: url)
        let bpm      = parsed?.bpm ?? 120
        let duration = parsed?.durationSeconds ?? 0
        let fileInfo = MIDIFileInfo(
            instrumentName: parsed?.instrumentName ?? "",
            soundFontName:  parsed?.soundFontTag   ?? ""
        )

        return RecordingItem(date: date,
                             state: .saved(urls: [url], bpm: bpm, duration: duration),
                             fileInfo: fileInfo)
    }

    // MARK: - Helpers

    static func computeDuration(
        tracks: [String: [TimedMIDIEvent]],
        startHostTime: UInt64
    ) -> TimeInterval {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let all = tracks.values.flatMap { $0 }
        guard let lastTime = all.map(\.hostTime).max(),
              lastTime > startHostTime else { return 0 }
        let nanos = Double(lastTime - startHostTime)
            * Double(timebase.numer) / Double(timebase.denom)
        return nanos / 1_000_000_000.0
    }
}

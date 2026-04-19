import Foundation
import AppKit

/// 레코딩 상태 관리 + 저장된/미저장 항목 목록을 담당.
/// addEvent()는 MIDI 스레드에서 호출 가능, 나머지는 메인 스레드 전용.
final class RecordingStore: ObservableObject {
    @Published private(set) var items: [RecordingItem] = []
    @Published private(set) var isRecording = false
    @Published var showBPMSheet = false

    private(set) var pendingSaveItemID: UUID?

    private weak var settings:    SettingsStore?
    weak var audioEngine: AudioEngine?

    /// 현재 설정의 기본 BPM (뷰에서 initialBPM으로 사용)
    var defaultBPM: Int { settings?.defaultBPM ?? 120 }

    // 인플라이트 데이터 — MIDI 스레드에서 접근하므로 lock으로 보호
    private var inFlightTracks:  [String: [TimedMIDIEvent]] = [:]
    private var activeNotes:     [String: Set<NoteKey>]     = [:]
    private var recordingFlag    = false
    private var startProgram:    Int    = 0   // 레코딩 시작 시점 악기 번호 (PC 주입용)
    private let lock             = NSLock()
    private var recordingStartTime: UInt64 = 0

    // 정지 시점에 캡처된 악기 정보 — savePending()에서 메타 이벤트로 기록
    private var capturedInstrumentName: String = ""
    private var capturedSoundFontTag:   String = ""

    /// Note-off 삽입에 사용하는 채널+노트 식별자
    private struct NoteKey: Hashable {
        let channel: UInt8
        let note:    UInt8
    }

    init(settings: SettingsStore) {
        self.settings = settings
        scanDiskFiles()
    }

    // MARK: - Disk scan

    func scanDiskFiles() {
        let dir = settings?.saveDirectory ?? MIDIFileWriter.savesDirectory()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let existingURLs = Set(items.flatMap(\.savedURLs))
        var added = false
        for url in entries where url.pathExtension.lowercased() == "mid" {
            guard !existingURLs.contains(url) else { continue }
            if let item = RecordingItem.fromDisk(url: url) {
                items.append(item)
                added = true
            }
        }
        if added { items.sort { $0.date > $1.date } }
    }

    // MARK: - Recording control (메인 스레드 전용)

    func toggleRecording() { isRecording ? stopRecording() : startRecording() }

    func startRecording() {
        // 현재 악기 번호를 메인 스레드에서 안전하게 읽은 뒤 lock 안으로 전달
        let prog = audioEngine?.currentProgram ?? 0
        let now  = mach_absolute_time()
        lock.lock()
        inFlightTracks     = [:]
        activeNotes        = [:]
        startProgram       = prog
        recordingStartTime = now
        recordingFlag      = true   // recordingFlag는 다른 값 세팅 후 마지막에 set
        lock.unlock()
        isRecording = true
        playRecordingSound(start: true)
    }

    func stopRecording() {
        let stopHostTime = mach_absolute_time()
        lock.lock()
        recordingFlag = false
        var tracks = inFlightTracks
        let notes  = activeNotes
        inFlightTracks = [:]
        activeNotes    = [:]
        lock.unlock()
        isRecording = false
        playRecordingSound(start: false)

        // 정지 시점의 악기 상태 캡처 (savePending에서 메타 이벤트로 저장)
        captureInstrumentState()

        // 아직 열려 있는 Note On → Note Off 삽입
        for (source, noteSet) in notes {
            for key in noteSet {
                tracks[source, default: []].append(
                    TimedMIDIEvent(
                        event:    .noteOff(channel: key.channel, note: key.note),
                        hostTime: stopHostTime
                    )
                )
            }
        }

        guard !tracks.isEmpty else { return }

        let item = RecordingItem(
            date: Date(),
            state: .unsaved(tracks: tracks, startHostTime: recordingStartTime),
            fileInfo: MIDIFileInfo(
                instrumentName: capturedInstrumentName,
                soundFontName:  capturedSoundFontTag
            )
        )
        items.insert(item, at: 0)
        pendingSaveItemID = item.id

        // 자동 저장 모드이면 다이얼로그 없이 바로 저장
        if settings?.saveMode == .auto {
            savePending(bpm: settings?.defaultBPM ?? 120)
        } else {
            showBPMSheet = true
        }
    }

    // MARK: - Event capture (MIDI 스레드 안전)

    func addEvent(_ event: MIDIEvent, hostTime: UInt64, source: String) {
        lock.lock()
        guard recordingFlag else { lock.unlock(); return }

        // 소스의 첫 이벤트 시 레코딩 시작 시점의 Program Change 삽입
        // DAW에서 열면 채널 0에 악기가 자동 지정됨
        if inFlightTracks[source] == nil {
            inFlightTracks[source] = [
                TimedMIDIEvent(
                    event: .programChange(channel: 0,
                                          program: UInt8(clamping: startProgram)),
                    hostTime: recordingStartTime
                )
            ]
        }

        inFlightTracks[source]!.append(
            TimedMIDIEvent(event: event, hostTime: hostTime)
        )
        // 활성 노트 추적 (Note Off 자동 삽입에 필요)
        switch event {
        case .noteOn(let ch, let note, let vel) where vel > 0:
            activeNotes[source, default: []].insert(NoteKey(channel: ch, note: note))
        case .noteOn(let ch, let note, _):
            activeNotes[source, default: []].remove(NoteKey(channel: ch, note: note))
        case .noteOff(let ch, let note):
            activeNotes[source, default: []].remove(NoteKey(channel: ch, note: note))
        default:
            break
        }
        lock.unlock()
    }

    // MARK: - Discard (앱 종료 시 미저장 데이터 정리)

    /// 레코딩 중이면 저장 없이 즉시 폐기. 앱 종료 시 호출.
    func discardRecording() {
        lock.lock()
        recordingFlag  = false
        inFlightTracks = [:]
        activeNotes    = [:]
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isRecording        = false
            self.showBPMSheet       = false
            self.pendingSaveItemID  = nil
        }
    }

    // MARK: - Save / Cancel

    func savePending(bpm: Int) {
        defer { pendingSaveItemID = nil; showBPMSheet = false }

        guard let id  = pendingSaveItemID,
              let idx = items.firstIndex(where: { $0.id == id }),
              case .unsaved(let tracks, let startTime) = items[idx].state else { return }

        let saveDir = settings?.saveDirectory ?? MIDIFileWriter.savesDirectory()
        do {
            let urls = try MIDIFileWriter.save(
                tracks: tracks, startHostTime: startTime,
                bpm: bpm, date: items[idx].date, directory: saveDir,
                instrumentName: capturedInstrumentName,
                soundFontTag:   capturedSoundFontTag
            )
            let duration = RecordingItem.computeDuration(tracks: tracks, startHostTime: startTime)
            items[idx].state = .saved(urls: urls, bpm: bpm, duration: duration)
        } catch {
            print("[RecordingStore] 저장 실패: \(error)")
        }
    }

    func cancelSave() { pendingSaveItemID = nil; showBPMSheet = false }

    func retrySave(itemID: UUID) {
        guard items.contains(where: { $0.id == itemID && !$0.isSaved }) else { return }
        pendingSaveItemID = itemID
        showBPMSheet = true
    }

    // MARK: - BPM edit

    func editBPM(itemID: UUID, newBPM: Int) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }),
              case .saved(let urls, _, _) = items[idx].state else { return }

        for url in urls {
            guard let result = try? MIDIFileReader.parse(url: url) else { continue }
            // 메타 이벤트(악기명 / 사운드폰트 태그)를 원본에서 읽어 그대로 보존
            let newData = MIDIFileWriter.buildSMFFromTicks(
                tickEvents: result.tickEvents, ppqn: result.ppqn, bpm: newBPM,
                instrumentName: result.instrumentName, soundFontTag: result.soundFontTag)
            try? newData.write(to: url)
        }
        let duration = items[idx].duration ?? 0
        items[idx].state = .saved(urls: urls, bpm: newBPM, duration: duration)
    }

    // MARK: - Delete

    func deleteItem(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        for url in items[idx].savedURLs { try? FileManager.default.removeItem(at: url) }
        items.remove(at: idx)
    }

    // MARK: - Instrument state capture

    /// 레코딩 정지 시점에 AudioEngine의 악기 상태를 캡처.
    /// 이후 savePending()에서 MIDI 파일 메타 이벤트로 기록됨.
    private func captureInstrumentState() {
        guard let engine = audioEngine else {
            capturedInstrumentName = ""
            capturedSoundFontTag   = ""
            return
        }

        // GM 악기명 (DLS 모드에서도 program 번호로 결정)
        let program = engine.currentProgram
        capturedInstrumentName = InstrumentList.all.first(where: { $0.id == program })?.name ?? ""

        // 사운드폰트 태그
        if engine.isFallbackMode {
            capturedSoundFontTag = "DLS:System"  // macOS 내장 DLS 식별자
        } else if let sf = engine.selectedSoundFont {
            capturedSoundFontTag = "SF2:\(sf.displayName)"
        } else {
            capturedSoundFontTag = ""
        }
    }

    // MARK: - Sound feedback

    /// settings.playRecordingSound가 켜져 있을 때 효과음 재생.
    /// 메인 스레드에서 안전하게 실행하기 위해 DispatchQueue.main으로 감쌈.
    private func playRecordingSound(start: Bool) {
        guard settings?.playRecordingSound == true else { return }
        let soundName: NSSound.Name = start ? .init("Ping") : .init("Pop")
        DispatchQueue.main.async {
            NSSound(named: soundName)?.play()
        }
    }
}

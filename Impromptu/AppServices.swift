import Foundation
import Combine
import AppKit

/// 앱 전역 서비스를 소유하고 MIDI → Audio/Recording 연결을 담당.
final class AppServices: ObservableObject {
    let midiManager  = MIDIManager()
    let audioEngine  = AudioEngine()
    let settings     = SettingsStore()
    let midiPlayer   = MIDIPlayer()
    let sfDownloader = SoundFontDownloadManager()

    // RecordingStore는 SettingsStore + AudioEngine 참조가 필요하므로 lazy로 초기화
    private(set) lazy var recordingStore: RecordingStore = {
        let store = RecordingStore(settings: self.settings)
        store.audioEngine = self.audioEngine
        return store
    }()

    private var cancellables = Set<AnyCancellable>()

    init() {
        midiPlayer.audioEngine = audioEngine

        // 다운로드 완료 → 사운드폰트 목록 재검색
        sfDownloader.onCompleted = { [weak self] _ in
            self?.audioEngine.refreshSoundFonts()
        }

        // 삭제 완료 → 현재 선택 중이었으면 DLS로 전환 후 목록 재검색
        sfDownloader.onDeleted = { [weak self] entry in
            guard let self else { return }
            if self.audioEngine.selectedSoundFont?.id == entry.id {
                self.audioEngine.selectDLS()
            }
            self.audioEngine.refreshSoundFonts()
        }

        midiManager.onMIDIEvent = { [weak self] event, hostTime, sourceName in
            guard let self else { return }

            // ── MIDI Learn 모드 — 해당 장치의 이벤트만 수락 ─────────────────
            if let target = self.settings.learningTarget, target.sourceName == sourceName {
                self.settings.learnTrigger(from: event, source: sourceName)
                self.audioEngine.handle(event)
                return
            }

            // ── 비활성화된 소스 필터 ─────────────────────────────────────────
            if self.settings.disabledSources.contains(sourceName) { return }

            // ── 오디오 재생 (트리거 이벤트도 소리는 냄) ─────────────────────
            self.audioEngine.handle(event)

            // ── 레코딩 시작 트리거 ────────────────────────────────────────────
            if self.settings.isStartTrigger(event, source: sourceName) {
                if !self.recordingStore.isRecording {
                    self.recordingStore.startRecording()
                }
                return   // 트리거 이벤트는 레코딩 데이터에서 제외
            }

            // ── 레코딩 종료 트리거 ────────────────────────────────────────────
            if self.settings.isStopTrigger(event, source: sourceName) {
                if self.recordingStore.isRecording {
                    self.recordingStore.stopRecording()
                }
                return   // 트리거 이벤트는 레코딩 데이터에서 제외
            }

            // ── 레코딩 데이터 추가 ────────────────────────────────────────────
            self.recordingStore.addEvent(event, hostTime: hostTime, source: sourceName)
        }

        // 앱 종료 시 레코딩 중이면 미저장 데이터 폐기
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            self?.recordingStore.discardRecording()
        }

        // 자식 objectWillChange → AppServices로 전파 (MenuBarExtra label 갱신 등)
        [midiManager.objectWillChange.eraseToAnyPublisher(),
         audioEngine.objectWillChange.eraseToAnyPublisher(),
         settings.objectWillChange.eraseToAnyPublisher(),
         midiPlayer.objectWillChange.eraseToAnyPublisher(),
         sfDownloader.objectWillChange.eraseToAnyPublisher()
        ].forEach { pub in
            pub.sink { [weak self] _ in self?.objectWillChange.send() }
               .store(in: &cancellables)
        }
        // recordingStore lazy init → also forward
        recordingStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}

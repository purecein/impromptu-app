import Foundation

/// .mid 파일을 비동기로 재생. 메인 스레드 전용 (stop/play 호출 포함).
///
/// 재생은 AudioEngine의 playbackSampler(전용 샘플러)를 통해 이루어지며,
/// 스튜디오의 현재 사운드폰트/악기 선택 상태(@Published)는 전혀 변경하지 않는다.
final class MIDIPlayer: ObservableObject {
    @Published private(set) var playingItemID: UUID?

    var audioEngine: AudioEngine?

    private var playTask: Task<Void, Never>?

    // MARK: - Playback

    /// url을 파싱해 itemID 태그로 재생 시작.
    /// 파일 내 메타 이벤트(0x04 악기명, 0x01 사운드폰트 태그)를 읽어
    /// 재생 전용 샘플러에 해당 사운드폰트/악기를 로드한 뒤 재생한다.
    /// 스튜디오의 selectedSoundFont / currentProgram 등 상태는 변경하지 않는다.
    func play(url: URL, itemID: UUID) {
        stop()
        playingItemID = itemID
        let engine = audioEngine

        playTask = Task { [weak self] in
            let playerRef = self

            guard let result = try? MIDIFileReader.parse(url: url) else {
                await MainActor.run { playerRef?.playingItemID = nil }
                return
            }

            // 재생 전용 샘플러에 저장 당시 사운드폰트/악기 로드 (메인 스레드 필요)
            // @Published 상태는 변경하지 않으므로 스튜디오 UI에 영향 없음
            await MainActor.run {
                engine?.preparePlayback(soundFontTag:   result.soundFontTag,
                                        instrumentName: result.instrumentName)
            }

            // MIDI 이벤트 순차 재생 (재생 전용 샘플러로 전달)
            let startNs = DispatchTime.now().uptimeNanoseconds
            for event in result.scheduledEvents {
                guard !Task.isCancelled else { break }

                let targetNs = startNs &+ event.timeNanoseconds
                let now = DispatchTime.now().uptimeNanoseconds
                if targetNs > now {
                    try? await Task.sleep(nanoseconds: targetNs - now)
                }
                guard !Task.isCancelled else { break }

                engine?.handlePlayback(event.event)
            }

            // 재생 완료 / 중단 후: 모든 음 정지
            await MainActor.run {
                engine?.stopPlayback()
                if !Task.isCancelled {
                    playerRef?.playingItemID = nil
                }
            }
        }
    }

    /// 재생 중단 (메인 스레드 전용).
    func stop() {
        playTask?.cancel()
        playTask = nil
        playingItemID = nil
        audioEngine?.stopPlayback()
    }

    func isPlaying(_ itemID: UUID) -> Bool {
        playingItemID == itemID
    }
}

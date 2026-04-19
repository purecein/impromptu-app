import Foundation

/// 파일에서 파싱한 MIDI 이벤트 + 재생 시작 기준으로부터의 절대 나노초 오프셋.
struct ScheduledMIDIEvent {
    let event: MIDIEvent
    let timeNanoseconds: UInt64
}

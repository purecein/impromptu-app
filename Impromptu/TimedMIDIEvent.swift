import Foundation

struct TimedMIDIEvent {
    let event: MIDIEvent
    let hostTime: UInt64   // mach_absolute_time() 단위 — MIDI 파일 변환 시 틱으로 환산
}

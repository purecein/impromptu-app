import Foundation

final class RecordingEngine: ObservableObject {
    @Published private(set) var isRecording = false

    private(set) var tracks: [String: [TimedMIDIEvent]] = [:]
    private var startHostTime: UInt64 = 0

    // addEvent 는 MIDI 스레드에서 호출되므로 lock으로 보호
    private let lock = NSLock()

    // MARK: - Control

    func start() {
        lock.lock()
        tracks = [:]
        lock.unlock()

        startHostTime = mach_absolute_time()

        DispatchQueue.main.async { self.isRecording = true }
    }

    @discardableResult
    func stop() -> [String: [TimedMIDIEvent]] {
        DispatchQueue.main.async { self.isRecording = false }

        lock.lock()
        let result = tracks
        lock.unlock()
        return result
    }

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    // MARK: - Event capture (MIDI 스레드 호출 가능)

    func addEvent(_ event: MIDIEvent, hostTime: UInt64, source: String) {
        guard isRecording else { return }
        let timedEvent = TimedMIDIEvent(event: event, hostTime: hostTime)
        lock.lock()
        tracks[source, default: []].append(timedEvent)
        lock.unlock()
    }

    // MARK: - Utilities

    /// 레코딩 시작 시각(hostTime) — MIDI 파일 변환 시 기준점으로 사용
    var recordingStartHostTime: UInt64 { startHostTime }
}

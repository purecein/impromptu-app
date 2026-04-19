import Foundation

/// 앱 전역 설정 — UserDefaults 영구 저장.
final class SettingsStore: ObservableObject {

    // MARK: - MIDI

    /// 체크 해제된 (비활성화된) 소스 이름
    @Published var disabledSources: Set<String> = []

    /// 레코딩 시작/종료 시 효과음 재생 여부 (기본값: 켜짐)
    @Published var playRecordingSound: Bool = true

    // MARK: - Save

    /// BPM 다이얼로그 기본값 + 자동 저장 시 사용되는 BPM (20–300)
    @Published var defaultBPM: Int = 120

    /// 장치별 시작/종료 트리거
    @Published private(set) var deviceTriggers: [String: DeviceTriggers] = [:]

    /// MIDI Learn 진행 중인 대상 (nil = 미진행)
    @Published private(set) var learningTarget: LearningTarget? = nil

    /// 편의 프로퍼티 — 하나라도 Learn 중이면 true
    var isLearning: Bool { learningTarget != nil }

    // MARK: - Audio

    /// 선택된 출력 장치 UID ("" = 시스템 기본값)
    @Published var outputDeviceUID: String = ""

    // MARK: - Save mode / path

    @Published var saveMode: SaveMode = .dialog
    @Published var saveDirectory: URL = MIDIFileWriter.savesDirectory()

    // MARK: - Nested types

    enum SaveMode: String, CaseIterable, Equatable {
        case dialog = "dialog"
        case auto   = "auto"

        var displayName: String {
            switch self {
            case .dialog: return "다이얼로그 (BPM 입력)"
            case .auto:   return "자동 저장 (기본 BPM 사용)"
            }
        }
    }

    /// CC 또는 Note 기반 트리거 이벤트
    struct TriggerEvent: Codable, Equatable {
        enum Kind: String, Codable { case note, cc }
        let kind:   Kind
        let number: UInt8

        var displayName: String {
            switch kind {
            case .note: return "Note \(number) (\(Self.noteName(number)))"
            case .cc:   return "CC #\(number)"
            }
        }

        private static func noteName(_ note: UInt8) -> String {
            let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
            return "\(names[Int(note) % 12])\(Int(note) / 12 - 1)"
        }
    }

    /// 장치 하나의 시작/종료 트리거 쌍
    struct DeviceTriggers: Codable, Equatable {
        var start: TriggerEvent? = nil
        var stop:  TriggerEvent? = nil
    }

    /// MIDI Learn 대상 (장치 + 역할)
    struct LearningTarget: Equatable {
        enum Role: Equatable { case start, stop }
        let sourceName: String
        let role:       Role
    }

    // MARK: - UserDefaults keys

    private enum Keys {
        static let disabledSources    = "settings.disabledSources"
        static let deviceTriggers     = "settings.deviceTriggers"
        static let outputDeviceUID    = "settings.outputDeviceUID"
        static let saveMode           = "settings.saveMode"
        static let saveDirectory      = "settings.saveDirectory"
        static let playRecordingSound = "settings.playRecordingSound"
        static let defaultBPM         = "settings.defaultBPM"
        /// 구 단일 트리거 키 — 마이그레이션 후 제거
        static let legacyTrigger      = "settings.triggerEvent"
    }

    // MARK: - Init

    init() { load() }

    // MARK: - Trigger API (AppServices에서 호출)

    /// 이벤트가 해당 소스의 레코딩 시작 트리거인지 판별
    func isStartTrigger(_ event: MIDIEvent, source: String) -> Bool {
        guard let t = deviceTriggers[source]?.start else { return false }
        return matches(t, event: event)
    }

    /// 이벤트가 해당 소스의 레코딩 종료 트리거인지 판별
    func isStopTrigger(_ event: MIDIEvent, source: String) -> Bool {
        guard let t = deviceTriggers[source]?.stop else { return false }
        return matches(t, event: event)
    }

    private func matches(_ t: TriggerEvent, event: MIDIEvent) -> Bool {
        switch event {
        case .noteOn(_, let note, let vel) where vel > 0:
            return t.kind == .note && t.number == note
        case .controlChange(_, let cc, let val) where val > 0:
            return t.kind == .cc && t.number == cc
        default:
            return false
        }
    }

    // MARK: - MIDI Learn API

    func startLearning(source: String, role: LearningTarget.Role) {
        learningTarget = LearningTarget(sourceName: source, role: role)
    }

    func cancelLearning() { learningTarget = nil }

    /// Learn 중 수신된 이벤트로 트리거를 설정.
    /// learningTarget의 sourceName과 일치하는 이벤트만 수락.
    func learnTrigger(from event: MIDIEvent, source: String) {
        guard let target = learningTarget, target.sourceName == source else { return }
        let te: TriggerEvent
        switch event {
        case .noteOn(_, let note, let vel) where vel > 0:
            te = TriggerEvent(kind: .note, number: note)
        case .controlChange(_, let cc, let val) where val > 0:
            te = TriggerEvent(kind: .cc, number: cc)
        default:
            return   // noteOff·pitchBend 등 → Learn 모드 유지
        }
        var triggers = deviceTriggers[source] ?? DeviceTriggers()
        switch target.role {
        case .start: triggers.start = te
        case .stop:  triggers.stop  = te
        }
        deviceTriggers[source] = triggers
        learningTarget = nil
        persist()
    }

    func clearTrigger(source: String, role: LearningTarget.Role) {
        var triggers = deviceTriggers[source] ?? DeviceTriggers()
        switch role {
        case .start: triggers.start = nil
        case .stop:  triggers.stop  = nil
        }
        // 시작·종료 모두 nil이면 장치 항목 자체 제거
        if triggers.start == nil && triggers.stop == nil {
            deviceTriggers.removeValue(forKey: source)
        } else {
            deviceTriggers[source] = triggers
        }
        persist()
    }

    // MARK: - Persistence

    func persist() {
        if let data = try? JSONEncoder().encode(Array(disabledSources)) {
            UserDefaults.standard.set(data, forKey: Keys.disabledSources)
        }
        if let data = try? JSONEncoder().encode(deviceTriggers) {
            UserDefaults.standard.set(data, forKey: Keys.deviceTriggers)
        }
        UserDefaults.standard.set(outputDeviceUID,    forKey: Keys.outputDeviceUID)
        UserDefaults.standard.set(saveMode.rawValue,  forKey: Keys.saveMode)
        UserDefaults.standard.set(saveDirectory.path, forKey: Keys.saveDirectory)
        UserDefaults.standard.set(playRecordingSound, forKey: Keys.playRecordingSound)
        UserDefaults.standard.set(defaultBPM,         forKey: Keys.defaultBPM)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Keys.disabledSources),
           let arr  = try? JSONDecoder().decode([String].self, from: data) {
            disabledSources = Set(arr)
        }

        // 신규 장치별 트리거
        if let data = UserDefaults.standard.data(forKey: Keys.deviceTriggers),
           let dict = try? JSONDecoder().decode([String: DeviceTriggers].self, from: data) {
            deviceTriggers = dict
        }

        // 구 단일 트리거 마이그레이션 — 장치 매핑 불가이므로 조용히 삭제
        if deviceTriggers.isEmpty,
           UserDefaults.standard.object(forKey: Keys.legacyTrigger) != nil {
            UserDefaults.standard.removeObject(forKey: Keys.legacyTrigger)
        }

        outputDeviceUID = UserDefaults.standard.string(forKey: Keys.outputDeviceUID) ?? ""
        if let raw  = UserDefaults.standard.string(forKey: Keys.saveMode),
           let mode = SaveMode(rawValue: raw) { saveMode = mode }
        if let path = UserDefaults.standard.string(forKey: Keys.saveDirectory) {
            saveDirectory = URL(fileURLWithPath: path)
        }
        // 저장된 값이 있으면 사용, 없으면 기본값(true) 유지
        if UserDefaults.standard.object(forKey: Keys.playRecordingSound) != nil {
            playRecordingSound = UserDefaults.standard.bool(forKey: Keys.playRecordingSound)
        }
        if UserDefaults.standard.object(forKey: Keys.defaultBPM) != nil {
            let saved = UserDefaults.standard.integer(forKey: Keys.defaultBPM)
            defaultBPM = max(20, min(300, saved))
        }
    }
}

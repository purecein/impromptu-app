import AVFoundation
import AudioToolbox
import CoreAudio

// MARK: - AudioOutputDevice

struct AudioOutputDevice: Identifiable, Equatable {
    let id: String        // uid — stable across launches (Identifiable)
    let deviceID: AudioDeviceID
    let name: String
    var uid: String { id }
}

// MARK: - AudioEngine

final class AudioEngine: ObservableObject {

    // Soundfont
    @Published private(set) var availableSoundFonts: [SoundFont] = []
    @Published private(set) var selectedSoundFont: SoundFont?
    @Published private(set) var currentProgram: Int = 0

    /// SF2가 로드되지 않아 macOS 내장 DLS 음색으로 동작 중이면 true.
    /// false = SF2 로드됨, true = DLS 폴백 (앱 시작 기본값).
    @Published private(set) var isFallbackMode: Bool = true

    // Output device
    @Published private(set) var outputDevices: [AudioOutputDevice] = []

    private let engine          = AVAudioEngine()
    private let sampler         = AVAudioUnitSampler()  // 실시간 MIDI 입력 전용
    private let playbackSampler = AVAudioUnitSampler()  // MIDI 파일 재생 전용

    // MARK: - 상수

    /// UserDefaults에 저장되는 DLS 폴백의 고정 식별자
    static let dlsIdentifier = "builtin_dls"

    // MARK: - UserDefaults keys

    private enum Keys {
        static let soundFontID     = "impromptu.soundFontID"
        static let program         = "impromptu.instrumentProgram"
        static let outputDeviceUID = "impromptu.outputDeviceUID"
    }

    // MARK: - init

    init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        // 재생 전용 샘플러: 메인 믹서에 연결하되 @Published 상태와 무관하게 동작
        engine.attach(playbackSampler)
        engine.connect(playbackSampler, to: engine.mainMixerNode, format: nil)
        do { try engine.start() } catch { print("[AudioEngine] start: \(error)") }

        outputDevices       = discoverOutputDevices()
        availableSoundFonts = discoverSoundFonts()
        restoreOutputDevice()
        restoreSoundFont()
    }

    // MARK: - Soundfont discovery

    private func discoverSoundFonts() -> [SoundFont] {
        var fonts: [SoundFont] = []
        var seenIDs = Set<String>()

        // 1. ~/Library/Application Support/Impromptu/SoundFonts/ — 앱 다운로드 폴더
        let appSupportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Impromptu/SoundFonts")
        appendSF2s(in: appSupportDir, to: &fonts, seenIDs: &seenIDs)

        // 2. ~/Library/Audio/Sounds/Banks/ — 사용자가 직접 설치한 SF2
        let banksDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Audio/Sounds/Banks")
        appendSF2s(in: banksDir, to: &fonts, seenIDs: &seenIDs)

        // 빈 배열도 정상 상태 — "사운드폰트 미설치"는 에러가 아님
        return fonts
    }

    private func appendSF2s(in dir: URL,
                             to fonts: inout [SoundFont],
                             seenIDs: inout Set<String>) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where url.pathExtension.lowercased() == "sf2" {
            let stem = url.deletingPathExtension().lastPathComponent
            if seenIDs.insert(stem).inserted {
                fonts.append(makeSoundFont(id: stem, url: url))
            }
        }
    }

    /// 카탈로그 항목의 id → 사람이 읽기 좋은 표시 이름 매핑.
    /// SoundFontCatalogEntry.catalog의 id/displayName과 일치해야 함.
    private static let knownDisplayNames: [String: String] = [
        "GeneralUserGS":        "GeneralUser GS",
        "SalamanderGrandPiano": "Salamander Grand Piano",
    ]

    private func makeSoundFont(id: String, url: URL) -> SoundFont {
        let isPianoOnly  = id.localizedCaseInsensitiveContains("salamander")
        let displayName  = Self.knownDisplayNames[id] ?? id
        return SoundFont(id: id, displayName: displayName, url: url, isPianoOnly: isPianoOnly)
    }

    // MARK: - Soundfont persistence

    private func restoreSoundFont() {
        let savedID = UserDefaults.standard.string(forKey: Keys.soundFontID)

        // 명시적 DLS 선택이거나 저장값 없음 → DLS 폴백 유지 (기본 상태)
        if savedID == nil || savedID == Self.dlsIdentifier {
            isFallbackMode = true
            return
        }

        // 저장된 SF2가 목록에 있고 파일도 존재할 때만 로드
        guard let sf = availableSoundFonts.first(where: { $0.id == savedID }) else {
            isFallbackMode = true; return
        }
        let savedProgram = UserDefaults.standard.integer(forKey: Keys.program)
        applyLoad(sf: sf, program: sf.isPianoOnly ? 0 : savedProgram, persist: false)
    }

    private func persistSoundFont() {
        // DLS 폴백이면 dlsIdentifier를, SF2 선택 중이면 해당 ID를 저장
        let idToSave = selectedSoundFont?.id ?? Self.dlsIdentifier
        UserDefaults.standard.set(idToSave,      forKey: Keys.soundFontID)
        UserDefaults.standard.set(currentProgram, forKey: Keys.program)
    }

    // MARK: - Public soundfont API

    /// 다운로드 완료 후 목록 재검색. 메인 스레드에서 호출.
    func refreshSoundFonts() {
        availableSoundFonts = discoverSoundFonts()
    }


    /// macOS 내장 GM DLS 파일 경로 (CoreAudio 번들 내 고정 위치).
    private static let systemDLSURL = URL(fileURLWithPath:
        "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")

    /// DLS 폴백 모드로 전환. 시스템 DLS를 명시 로드해 SF2 뱅크를 교체.
    func selectDLS() {
        selectedSoundFont = nil
        isFallbackMode    = true
        persistSoundFont()
        reloadCurrentAudio()
        print("[AudioEngine] switched to DLS fallback")
    }

    /// 현재 모드에 맞게 sampler를 (재)로드.
    /// DLS 모드: 시스템 DLS 파일 로드. SF2 모드: 해당 SF2 로드.
    /// 엔진 재시작 후나 selectDLS() 후에 호출해 sampler 상태를 실제와 일치시킴.
    private func reloadCurrentAudio() {
        if let sf = selectedSoundFont {
            _ = loadURL(sf.url, program: currentProgram)
        } else {
            // DLS: 시스템 DLS 파일이 있을 때만 로드 (없으면 sampler 기본 DLS 유지)
            if FileManager.default.fileExists(atPath: Self.systemDLSURL.path) {
                _ = loadURL(Self.systemDLSURL, program: currentProgram)
            }
        }
    }

    func setSoundFont(_ sf: SoundFont) {
        applyLoad(sf: sf, program: sf.isPianoOnly ? 0 : currentProgram, persist: true)
    }

    func setInstrument(program: Int) {
        if let sf = selectedSoundFont, !sf.isPianoOnly {
            // SF2 모드: SF2 재로드로 program 변경
            applyLoad(sf: sf, program: program, persist: true)
        } else if isFallbackMode {
            // DLS 폴백 모드: Program Change 메시지 직접 전송 (GM 128종 지원)
            sampler.sendProgramChange(UInt8(clamping: program), onChannel: 0)
            currentProgram = program
            UserDefaults.standard.set(program, forKey: Keys.program)
        }
    }

    private func applyLoad(sf: SoundFont, program: Int, persist: Bool) {
        // 파일이 삭제됐으면 DLS 폴백으로 전환
        guard FileManager.default.fileExists(atPath: sf.url.path) else {
            print("[AudioEngine] SF2 not found, falling back to DLS: \(sf.url.lastPathComponent)")
            selectedSoundFont = nil
            isFallbackMode    = true
            return
        }
        guard loadURL(sf.url, program: program) else {
            isFallbackMode = true
            return
        }
        selectedSoundFont = sf
        currentProgram    = program
        isFallbackMode    = false
        if persist { persistSoundFont() }
    }

    @discardableResult
    private func loadURL(_ url: URL, program: Int) -> Bool {
        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: UInt8(clamping: program),
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
            print("[AudioEngine] loaded \(url.lastPathComponent) prog=\(program)")
            return true
        } catch {
            print("[AudioEngine] load failed: \(url.lastPathComponent) — \(error)")
            return false
        }
    }

    // MARK: - Output device discovery

    private func discoverOutputDevices() -> [AudioOutputDevice] {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &size, &deviceIDs
        )

        var result: [AudioOutputDevice] = []
        for devID in deviceIDs {
            guard hasOutputStreams(devID) else { continue }
            let name = deviceString(devID, kAudioDevicePropertyDeviceNameCFString)
            let uid  = deviceString(devID, kAudioDevicePropertyDeviceUID)
            guard !uid.isEmpty else { continue }
            result.append(AudioOutputDevice(id: uid, deviceID: devID, name: name))
        }
        return result
    }

    private func hasOutputStreams(_ devID: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope:    kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(devID, &addr, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return false }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(devID, &addr, 0, nil, &size, raw) == noErr else { return false }
        return raw.load(as: AudioBufferList.self).mNumberBuffers > 0
    }

    private func deviceString(_ devID: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var cfStr: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        AudioObjectGetPropertyData(devID, &addr, 0, nil, &size, &cfStr)
        return cfStr as String
    }

    // MARK: - Output device selection

    private func restoreOutputDevice() {
        let saved = UserDefaults.standard.string(forKey: Keys.outputDeviceUID) ?? ""
        guard !saved.isEmpty,
              outputDevices.contains(where: { $0.uid == saved }) else { return }
        setOutputDevice(uid: saved)
    }

    func setOutputDevice(uid: String) {
        guard let device = outputDevices.first(where: { $0.uid == uid }) else { return }
        engine.stop()
        do {
            try engine.outputNode.auAudioUnit.setDeviceID(device.deviceID)
            try engine.start()
            // 엔진 재시작 후 현재 모드에 맞게 sampler 재로드 (SF2 or DLS)
            reloadCurrentAudio()
            UserDefaults.standard.set(uid, forKey: Keys.outputDeviceUID)
        } catch {
            print("[AudioEngine] setOutputDevice failed: \(error)")
            try? engine.start()
        }
    }

    func resetOutputDevice() {
        // Revert to system default
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var defaultID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &defaultID)

        engine.stop()
        do {
            try engine.outputNode.auAudioUnit.setDeviceID(defaultID)
            try engine.start()
            // 엔진 재시작 후 현재 모드에 맞게 sampler 재로드 (SF2 or DLS)
            reloadCurrentAudio()
            UserDefaults.standard.removeObject(forKey: Keys.outputDeviceUID)
        } catch {
            print("[AudioEngine] resetOutputDevice failed: \(error)")
            try? engine.start()
        }
    }

    // MARK: - Playback sampler API (스튜디오 @Published 상태 변경 없음)

    /// 재생 전용 샘플러에 사운드폰트/악기를 로드한다.
    /// selectedSoundFont, isFallbackMode, currentProgram 등 @Published 상태는 일절 변경하지 않는다.
    /// - Parameters:
    ///   - soundFontTag: "SF2:XXX" 또는 "DLS:System". 빈 문자열이면 DLS 폴백.
    ///   - instrumentName: GM 악기명 (예: "Acoustic Grand Piano"). 빈 문자열이면 program 0 사용.
    func preparePlayback(soundFontTag: String, instrumentName: String) {
        // 사운드폰트 URL 결정
        let sfDisplayName = soundFontTag.hasPrefix("SF2:")
            ? String(soundFontTag.dropFirst(4)) : ""

        let soundURL: URL
        if sfDisplayName.isEmpty {
            // 태그 없음 또는 "DLS:System" → 시스템 DLS
            guard FileManager.default.fileExists(atPath: Self.systemDLSURL.path) else {
                print("[AudioEngine] playback: 시스템 DLS 없음 — 로드 생략")
                return
            }
            soundURL = Self.systemDLSURL
        } else if let sf = availableSoundFonts.first(where: {
            $0.displayName == sfDisplayName || $0.id == sfDisplayName
        }) {
            soundURL = sf.url
        } else {
            // 해당 SF2 미설치 → DLS 폴백 (경고 없이 자연스럽게)
            print("[AudioEngine] playback: '\(sfDisplayName)' 미설치 — DLS 폴백")
            guard FileManager.default.fileExists(atPath: Self.systemDLSURL.path) else { return }
            soundURL = Self.systemDLSURL
        }

        // 초기 악기 번호 결정 (MIDI 파일 내 Program Change 이벤트가 이후 덮어씀)
        let prog = InstrumentList.all.first(where: { $0.name == instrumentName })?.id ?? 0

        do {
            try playbackSampler.loadSoundBankInstrument(
                at: soundURL,
                program: UInt8(clamping: prog),
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
        } catch {
            print("[AudioEngine] playback load failed: \(error)")
        }
    }

    /// 재생 전용 샘플러에 MIDI 이벤트를 전달한다. (백그라운드 스레드 안전)
    func handlePlayback(_ event: MIDIEvent) {
        switch event {
        case .noteOn(let ch, let note, let vel):
            playbackSampler.startNote(note, withVelocity: vel, onChannel: ch)
        case .noteOff(let ch, let note):
            playbackSampler.stopNote(note, onChannel: ch)
        case .controlChange(let ch, let cc, let val):
            playbackSampler.sendController(cc, withValue: val, onChannel: ch)
        case .pitchBend(let ch, let val):
            playbackSampler.sendPitchBend(val, onChannel: ch)
        case .aftertouch(let ch, let pressure):
            playbackSampler.sendPressure(pressure, onChannel: ch)
        case .programChange(let ch, let prog):
            playbackSampler.sendProgramChange(prog, onChannel: ch)
        }
    }

    /// 재생 전용 샘플러의 모든 채널에 All Notes Off를 전송한다.
    /// 재생 완료 또는 중단 시 호출.
    func stopPlayback() {
        for ch: UInt8 in 0..<16 {
            playbackSampler.sendController(123, withValue: 0, onChannel: ch)
        }
    }

    // MARK: - MIDI event handling (thread-safe)

    func handle(_ event: MIDIEvent) {
        // SF2 미로드 상태(isFallbackMode)에서도 sampler에 이벤트를 전달.
        // AVAudioUnitSampler는 SF2 없이도 내장 DLS 음색으로 재생함.
        switch event {
        case .noteOn(let ch, let note, let vel):
            sampler.startNote(note, withVelocity: vel, onChannel: ch)
        case .noteOff(let ch, let note):
            sampler.stopNote(note, onChannel: ch)
        case .controlChange(let ch, let cc, let val):
            sampler.sendController(cc, withValue: val, onChannel: ch)
        case .pitchBend(let ch, let val):
            sampler.sendPitchBend(val, onChannel: ch)
        case .aftertouch(let ch, let pressure):
            sampler.sendPressure(pressure, onChannel: ch)
        case .programChange(let ch, let prog):
            sampler.sendProgramChange(prog, onChannel: ch)
        }
    }

    deinit { engine.stop() }
}

import SwiftUI
import AppKit

// MARK: - Section enum

private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case midi      = "MIDI"
    case audio     = "오디오"
    case save      = "저장"
    case soundFont = "사운드폰트"
    case about     = "정보"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .midi:      return "pianokeys"
        case .audio:     return "speaker.wave.2"
        case .save:      return "folder"
        case .soundFont: return "music.note.list"
        case .about:     return "info.circle"
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject var midiManager: MIDIManager
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var settings:    SettingsStore
    @EnvironmentObject var downloader:  SoundFontDownloadManager

    @State private var selectedSection: SettingsSection? = .midi

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .frame(minWidth: 650, minHeight: 450)
        // 다운로드 실패 알림
        .alert("다운로드 실패", isPresented: Binding(
            get: { downloader.errorMessage != nil },
            set: { if !$0 { downloader.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { downloader.errorMessage = nil }
        } message: {
            Text(downloader.errorMessage ?? "")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(SettingsSection.allCases, selection: $selectedSection) { section in
            Label(section.rawValue, systemImage: section.icon)
                .tag(section)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 150, ideal: 175, max: 210)
    }

    // MARK: - Detail router

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection ?? .midi {
        case .midi:      midiSection
        case .audio:     audioSection
        case .save:      saveSection
        case .soundFont: soundFontSection
        case .about:     aboutSection
        }
    }

    // MARK: - MIDI 섹션

    private var midiSection: some View {
        Form {
            Section("입력 장치") {
                if midiManager.connectedSources.isEmpty {
                    Text("연결된 MIDI 장치 없음")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(midiManager.connectedSources, id: \.self) { source in
                        deviceRow(for: source)
                    }
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { settings.playRecordingSound },
                    set: { settings.playRecordingSound = $0; settings.persist() }
                )) {
                    Label("레코딩 시작 / 종료 시 효과음 재생",
                          systemImage: "speaker.wave.2")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("MIDI")
    }

    @ViewBuilder
    private func deviceRow(for displayName: String) -> some View {
        let key        = MIDIManager.normalizedName(displayName)
        let isEnabled  = !settings.disabledSources.contains(key)
        let triggers   = settings.deviceTriggers[key]
        let learnStart = SettingsStore.LearningTarget(sourceName: key, role: .start)
        let learnStop  = SettingsStore.LearningTarget(sourceName: key, role: .stop)

        VStack(alignment: .leading, spacing: 8) {
            Toggle(displayName, isOn: enabledBinding(for: key))
                .fontWeight(.medium)

            if isEnabled {
                TriggerRow(
                    label:      "시작",
                    trigger:    triggers?.start,
                    isLearning: settings.learningTarget == learnStart,
                    onLearn:    { settings.startLearning(source: key, role: .start) },
                    onCancel:   { settings.cancelLearning() },
                    onClear:    { settings.clearTrigger(source: key, role: .start) }
                )
                .padding(.leading, 20)

                TriggerRow(
                    label:      "종료",
                    trigger:    triggers?.stop,
                    isLearning: settings.learningTarget == learnStop,
                    onLearn:    { settings.startLearning(source: key, role: .stop) },
                    onCancel:   { settings.cancelLearning() },
                    onClear:    { settings.clearTrigger(source: key, role: .stop) }
                )
                .padding(.leading, 20)

                if let target = settings.learningTarget, target.sourceName == key {
                    let roleName = target.role == .start ? "시작" : "종료"
                    Label("\(displayName)에서 \(roleName)로 사용할 버튼을 누르세요",
                          systemImage: "waveform")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                        .padding(.leading, 20)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 오디오 섹션

    private var audioSection: some View {
        Form {
            Section("출력") {
                Picker("출력 장치", selection: $settings.outputDeviceUID) {
                    Text("시스템 기본값").tag("")
                    ForEach(audioEngine.outputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .onChange(of: settings.outputDeviceUID) { uid in
                    if uid.isEmpty { audioEngine.resetOutputDevice() }
                    else           { audioEngine.setOutputDevice(uid: uid) }
                    settings.persist()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("오디오")
    }

    // MARK: - 저장 섹션

    private var saveSection: some View {
        Form {
            Section {
                HStack {
                    Text("기본 BPM")
                    Spacer()
                    HStack(spacing: 4) {
                        TextField("", value: $settings.defaultBPM, format: .number)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: settings.defaultBPM) { bpm in
                                settings.defaultBPM = max(20, min(300, bpm))
                                settings.persist()
                            }
                        Stepper("", value: $settings.defaultBPM, in: 20...300, step: 1)
                            .labelsHidden()
                            .onChange(of: settings.defaultBPM) { _ in settings.persist() }
                    }
                    .fixedSize()
                }

                Picker("저장 방식", selection: $settings.saveMode) {
                    ForEach(SettingsStore.SaveMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .onChange(of: settings.saveMode) { _ in settings.persist() }

                LabeledContent("저장 경로") {
                    HStack(spacing: 8) {
                        Text(settings.saveDirectory.path)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 260, alignment: .trailing)
                        Button("변경") { chooseSaveDirectory() }
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("저장")
    }

    // MARK: - 사운드폰트 섹션

    private var soundFontSection: some View {
        Form {
            Section {
                ForEach(SoundFontCatalogEntry.catalog) { entry in
                    SoundFontEntryRow(entry: entry, downloader: downloader)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("사운드폰트")
    }

    // MARK: - 정보 섹션

    private var aboutSection: some View {
        ScrollView {
            VStack(spacing: 0) {
                appHeader
                    .padding(.top, 36)
                    .padding(.bottom, 28)

                infoTable
                    .padding(.horizontal, 40)
                    .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("정보")
    }

    /// 앱 아이콘 + 이름 + 버전 헤더
    private var appHeader: some View {
        VStack(spacing: 10) {
            // 앱 아이콘 — Assets에서 AppIcon 로드, 없으면 시스템 폴백
            Group {
                if let url  = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                   let icon = NSImage(contentsOf: url) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "music.note")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)

            Text("Impromptu")
                .font(.system(size: 22, weight: .semibold))

            Text("버전 \(appVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// 라벨 + 값 정보 테이블
    private var infoTable: some View {
        VStack(spacing: 0) {
            infoRow(label: "개발자") {
                Text("Hojun, Lee")
            }
            Divider()
            infoRow(label: "이메일") {
                Link("purecein@gmail.com",
                     destination: URL(string: "mailto:purecein@gmail.com")!)
                    .foregroundStyle(Color.accentColor)
            }
            Divider()
            infoRow(label: "GitHub") {
                Link("github.com/purecein/impromptu-app",
                     destination: URL(string: "https://github.com/purecein/impromptu-app")!)
                    .foregroundStyle(Color.accentColor)
            }
            Divider()
            infoRow(label: "번들 ID") {
                Text(Bundle.main.bundleIdentifier ?? "net.ceinfactory.app.impromptu")
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func infoRow<V: View>(label: String, @ViewBuilder value: () -> V) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Spacer()
            value()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    /// Bundle에서 런타임에 읽어오는 버전 문자열
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    // MARK: - Helpers

    private func enabledBinding(for source: String) -> Binding<Bool> {
        Binding(
            get: { !settings.disabledSources.contains(source) },
            set: { isEnabled in
                if isEnabled { settings.disabledSources.remove(source) }
                else         { settings.disabledSources.insert(source) }
                settings.persist()
            }
        )
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = false
        panel.allowsMultipleSelection = false
        panel.directoryURL            = settings.saveDirectory
        panel.prompt                  = "선택"
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectory = url
            settings.persist()
        }
    }
}

// MARK: - SoundFontEntryRow

private struct SoundFontEntryRow: View {
    let entry: SoundFontCatalogEntry
    @ObservedObject var downloader: SoundFontDownloadManager

    private var isInstalled:   Bool { downloader.installedIDs.contains(entry.id) }
    private var isActive:      Bool { downloader.downloadingID == entry.id }
    private var isExtracting:  Bool { isActive && downloader.isExtracting }
    private var isDownloading: Bool { isActive && !downloader.isExtracting }
    private var isOtherBusy:   Bool { downloader.downloadingID != nil && !isActive }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .fontWeight(.medium)
                Text("약 \(entry.expectedSizeMB) MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isInstalled {
                HStack(spacing: 8) {
                    Text("설치됨")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Button(role: .destructive) {
                        downloader.delete(entry)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("\(entry.displayName) 삭제")
                }
            } else if isExtracting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("압축 해제 중...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if isDownloading {
                HStack(spacing: 6) {
                    ProgressView(value: downloader.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 100)
                    Text("\(Int(downloader.progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                    Button("취소") { downloader.cancelDownload() }
                        .controlSize(.mini)
                }
            } else {
                Button("다운로드") { downloader.startDownload(for: entry) }
                    .controlSize(.small)
                    .disabled(isOtherBusy)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - TriggerRow

private struct TriggerRow: View {
    let label:      String
    let trigger:    SettingsStore.TriggerEvent?
    let isLearning: Bool
    let onLearn:    () -> Void
    let onCancel:   () -> Void
    let onClear:    () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .frame(width: 28, alignment: .leading)

            if let t = trigger {
                Text(t.displayName)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Button("지우기", role: .destructive) { onClear() }
                    .controlSize(.mini)
                    .accessibilityLabel("\(label) 트리거 지우기")
            } else {
                Text("없음")
                    .foregroundStyle(.tertiary)
                    .font(.subheadline)
            }

            Spacer()

            Button(isLearning ? "취소" : "감지") {
                isLearning ? onCancel() : onLearn()
            }
            .controlSize(.small)
            .tint(isLearning ? .orange : .accentColor)
            .accessibilityLabel(isLearning
                ? "\(label) 트리거 감지 취소"
                : "\(label) 트리거 감지 시작")
        }
    }
}

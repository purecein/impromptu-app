import SwiftUI
import AppKit

struct StudioView: View {
    @EnvironmentObject var midiManager:    MIDIManager
    @EnvironmentObject var recordingStore: RecordingStore
    @EnvironmentObject var audioEngine:    AudioEngine
    @EnvironmentObject var midiPlayer:     MIDIPlayer
    @EnvironmentObject var settings:       SettingsStore

    /// 연결된 소스 중 비활성화되지 않은 것이 하나라도 있으면 true
    private var hasActiveSources: Bool {
        midiManager.connectedSources.contains {
            !settings.disabledSources.contains(MIDIManager.normalizedName($0))
        }
    }

    // 사운드폰트 선택
    @State private var selectedSoundFontID = ""

    // 악기 선택
    @State private var selectedCategory = InstrumentList.categories.first ?? "Piano"
    @State private var selectedProgram  = 0

    // 시트 / 다이얼로그 상태
    @State private var bpmEditItem:         RecordingItem? = nil
    @State private var deleteConfirmItemID: UUID?          = nil

    // 현재 선택된 사운드폰트가 피아노 전용인지
    private var isPianoOnly: Bool {
        audioEngine.availableSoundFonts.first(where: { $0.id == selectedSoundFontID })?.isPianoOnly == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topSection
            Divider()
            recordingsList
            Divider()
            debugSection
        }
        .frame(minWidth: 480, minHeight: 520, alignment: .topLeading)
        .onAppear {
            syncStateFromEngine()
            // LSUIElement 앱은 applicationIconImage가 자동 세팅되지 않을 수 있음.
            // 삭제 confirmationDialog(NSAlert 기반)에 AppIcon이 표시되려면 여기서 보장.
            if let url  = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = icon
            }
        }
        // 다운로드 완료 후 새 SF2가 목록에 추가되면 Picker 상태 동기화
        .onChange(of: audioEngine.availableSoundFonts) { _ in syncStateFromEngine() }

        // ── BPM 저장 시트 ────────────────────────────────────────────────────
        .sheet(isPresented: $recordingStore.showBPMSheet,
               onDismiss: recordingStore.cancelSave) {
            BPMSaveSheet(
                title: String(localized: "studio.sheet.bpm_save"),
                initialBPM: recordingStore.defaultBPM,
                onSave:   { bpm in recordingStore.savePending(bpm: bpm) },
                onCancel: recordingStore.cancelSave
            )
        }

        // ── BPM 편집 시트 ────────────────────────────────────────────────────
        .sheet(item: $bpmEditItem) { item in
            BPMSaveSheet(
                title: String(localized: "studio.sheet.bpm_edit"),
                initialBPM: item.savedBPM ?? recordingStore.defaultBPM,
                onSave: { bpm in
                    recordingStore.editBPM(itemID: item.id, newBPM: bpm)
                    bpmEditItem = nil
                },
                onCancel: { bpmEditItem = nil }
            )
        }

        // ── 삭제 확인 다이얼로그 ─────────────────────────────────────────────
        // confirmationDialog 는 Ventura 디버그 빌드에서 LaunchServices 캐시 문제로
        // 회색 기본 아이콘이 나온다. NSAlert를 직접 생성해 alert.icon을 명시 지정.
        .onChange(of: deleteConfirmItemID) { itemID in
            guard let itemID else { return }
            deleteConfirmItemID = nil   // 상태 즉시 초기화
            showDeleteAlert(itemID: itemID)
        }
    }

    // MARK: - State sync

    // MARK: - Delete alert (NSAlert 직접 생성 — AppIcon 명시 지정)

    private func showDeleteAlert(itemID: UUID) {
        let alert = NSAlert()
        alert.messageText     = String(localized: "studio.alert.delete.title")
        alert.informativeText = String(localized: "studio.alert.delete.message")
        alert.alertStyle      = .warning

        // AppIcon.icns 직접 로드 — LaunchServices 캐시 미사용
        if let url  = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            alert.icon = icon
        }

        let deleteBtn = alert.addButton(withTitle: String(localized: "studio.alert.delete.confirm"))
        deleteBtn.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "studio.alert.delete.cancel"))

        let perform: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            if self.midiPlayer.isPlaying(itemID) { self.midiPlayer.stop() }
            self.recordingStore.deleteItem(itemID)
        }

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: perform)
        } else {
            perform(alert.runModal())
        }
    }

    // MARK: - State sync

    private func syncStateFromEngine() {
        // DLS 폴백이면 DLS 식별자, SF2 로드 중이면 해당 ID
        selectedSoundFontID = audioEngine.isFallbackMode
            ? AudioEngine.dlsIdentifier
            : (audioEngine.selectedSoundFont?.id ?? AudioEngine.dlsIdentifier)
        // 악기
        let prog = audioEngine.currentProgram
        selectedProgram = prog
        if let cat = InstrumentList.all.first(where: { $0.id == prog })?.category {
            selectedCategory = cat
        }
    }

    // MARK: - Top section

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 10) {

            // 상태 표시
            HStack(spacing: 8) {
                Circle()
                    .fill(recordingStore.isRecording ? Color.red : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(recordingStore.isRecording ? "studio.status.recording" : "studio.status.idle")
                    .font(.subheadline)
                    .foregroundStyle(recordingStore.isRecording ? .red : .secondary)
            }

            // 레코딩 버튼 (시각적 토글 — ⌘R 시작, ⌘. 종료)
            Button {
                recordingStore.toggleRecording()
            } label: {
                Label(
                    recordingStore.isRecording ? "studio.button.record_stop" : "studio.button.record_start",
                    systemImage: recordingStore.isRecording
                        ? "stop.circle.fill" : "record.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(recordingStore.isRecording ? .gray : .red)
            .keyboardShortcut("r", modifiers: .command)   // ⌘R — 시작 (토글 공용)
            .disabled(!hasActiveSources && !recordingStore.isRecording)
            .help(
                !hasActiveSources && !recordingStore.isRecording
                    ? (midiManager.connectedSources.isEmpty
                       ? "studio.help.no_device"
                       : "studio.help.all_disabled")
                    : ""
            )

            // ⌘. — 레코딩 종료 전용 단축키 (숨김 버튼)
            Button("") { recordingStore.stopRecording() }
                .keyboardShortcut(".", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

            // 사운드폰트 선택 — DLS는 항상 첫 번째 항목으로 노출
            HStack(spacing: 6) {
                Picker("studio.picker.soundfont", selection: $selectedSoundFontID) {
                    Text("studio.soundfont.system_dls").tag(AudioEngine.dlsIdentifier)
                    if !audioEngine.availableSoundFonts.isEmpty {
                        Divider()
                        ForEach(audioEngine.availableSoundFonts) { sf in
                            Text(sf.displayName).tag(sf.id)
                        }
                    }
                }
                .labelsHidden()
                .accessibilityLabel("studio.accessibility.soundfont")
                .frame(maxWidth: .infinity)
                .onChange(of: selectedSoundFontID) { id in
                    if id == AudioEngine.dlsIdentifier {
                        audioEngine.selectDLS()
                    } else if let sf = audioEngine.availableSoundFonts.first(where: { $0.id == id }) {
                        audioEngine.setSoundFont(sf)
                        if sf.isPianoOnly {
                            selectedCategory = InstrumentList.categories.first ?? "Piano"
                            selectedProgram  = 0
                        }
                    }
                }

                // DLS 선택 시 품질 안내
                if selectedSoundFontID == AudioEngine.dlsIdentifier {
                    Label("studio.soundfont.low_quality", systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }

            // 악기 선택 (isPianoOnly일 때 비활성화)
            HStack(spacing: 8) {
                // 카테고리
                Picker("", selection: $selectedCategory) {
                    ForEach(InstrumentList.categories, id: \.self) { cat in
                        Text(verbatim: InstrumentList.localizedCategory(cat)).tag(cat)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("studio.accessibility.category")
                .frame(width: 140)
                .disabled(isPianoOnly)
                .onChange(of: selectedCategory) { _ in
                    guard !isPianoOnly else { return }
                    if let first = InstrumentList.instruments(in: selectedCategory).first {
                        selectedProgram = first.id
                        audioEngine.setInstrument(program: first.id)
                    }
                }

                // 악기
                Picker("", selection: $selectedProgram) {
                    ForEach(InstrumentList.instruments(in: selectedCategory)) { inst in
                        Text(inst.name).tag(inst.id)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("studio.accessibility.instrument")
                .frame(maxWidth: .infinity)
                .disabled(isPianoOnly)
                .onChange(of: selectedProgram) { program in
                    guard !isPianoOnly else { return }
                    audioEngine.setInstrument(program: program)
                }
            }
        }
        .padding()
    }

    // MARK: - Recordings list

    private var recordingsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("studio.list.title")
                    .font(.headline)
                Spacer()
                Text(verbatim: String(format: String(localized: "studio.list.count"), recordingStore.items.count))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            if recordingStore.items.isEmpty {
                Text("studio.list.empty")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(recordingStore.items) { item in
                            RecordingRow(
                                item:        item,
                                store:       recordingStore,
                                onBPMEdit:   { bpmEditItem = item },
                                onShowScore: { ScoreWindowManager.shared.open(item: item) },
                                onDelete:    { deleteConfirmItemID = item.id }
                            )
                            Divider().padding(.leading)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
    }

    // MARK: - Debug section

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("studio.debug.midi_input")
                .font(.headline)
            Text(midiManager.lastEventDescription)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Recording row

private struct RecordingRow: View {
    let item:        RecordingItem
    let store:       RecordingStore
    let onBPMEdit:   () -> Void
    let onShowScore: () -> Void
    let onDelete:    () -> Void

    @EnvironmentObject var midiPlayer: MIDIPlayer

    private var isPlaying: Bool { midiPlayer.isPlaying(item.id) }

    // DateComponentsFormatter: 시스템 로케일 기반 재생 시간 표시
    // 예) 영어: "2 min, 14 sec" / 한국어: "2분 14초"
    private static let durationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.unitsStyle      = .abbreviated
        f.allowedUnits    = [.minute, .second]
        f.zeroFormattingBehavior = .dropLeading
        return f
    }()

    // RelativeDateTimeFormatter: 시스템 로케일 기반 상대 시간 표시
    // 예) 영어: "just now", "today", "yesterday", "2 days ago"
    //     한국어: "방금 전", "오늘", "어제", "2일 전"
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle    = .full
        f.dateTimeStyle = .named
        return f
    }()

    private var durationText: String {
        guard let d = item.duration, d > 0 else { return "" }
        return Self.durationFormatter.string(from: d) ?? ""
    }

    private var relativeTimeText: String {
        Self.relativeFormatter.localizedString(for: item.date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            // 상단 행: 파일명 + 상대시간 + 미저장 뱃지
            HStack {
                Text(item.displayName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Text(relativeTimeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.isSaved {
                    Text("studio.row.unsaved")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            // 하단 행: BPM + 재생시간 + 버튼들
            HStack(spacing: 6) {
                if let bpm = item.savedBPM {
                    Text("\(bpm) BPM")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                if !durationText.isEmpty {
                    Text(durationText)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Spacer()

                // 미저장: 저장 버튼
                if !item.isSaved {
                    Button("studio.row.button.save") { store.retrySave(itemID: item.id) }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                // 저장된 항목 전용 버튼
                if item.isSaved {
                    // ▶ / ■
                    Button {
                        if isPlaying {
                            midiPlayer.stop()
                        } else if let url = item.savedURLs.first {
                            midiPlayer.play(url: url, itemID: item.id)
                        }
                    } label: {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(isPlaying ? .orange : .primary)
                    .accessibilityLabel(isPlaying ? "studio.row.accessibility.stop" : "studio.row.accessibility.play")

                    // 악보 창
                    Button { onShowScore() } label: {
                        Image(systemName: "music.note.list")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("studio.row.accessibility.score")

                    // BPM 편집
                    Button { onBPMEdit() } label: {
                        Image(systemName: "metronome")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("studio.row.accessibility.bpm")

                    // Finder에서 열기
                    Button {
                        if let url = item.savedURLs.first {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("studio.row.accessibility.finder")
                }

                // 삭제
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("studio.row.accessibility.delete")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

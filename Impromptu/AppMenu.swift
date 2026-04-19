import SwiftUI

struct AppMenu: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var midiManager:    MIDIManager
    @EnvironmentObject var recordingStore: RecordingStore
    @EnvironmentObject var settings:       SettingsStore

    /// 연결된 소스 중 비활성화되지 않은 것이 하나라도 있으면 true
    private var hasActiveSources: Bool {
        midiManager.connectedSources.contains {
            !settings.disabledSources.contains(MIDIManager.normalizedName($0))
        }
    }

    var body: some View {
        Text("Impromptu — \(recordingStore.isRecording ? "레코딩 중" : "대기 중")")
            .foregroundStyle(.secondary)

        Divider()

        Button(recordingStore.isRecording ? "레코딩 종료" : "레코딩 시작") {
            recordingStore.toggleRecording()
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(!hasActiveSources && !recordingStore.isRecording)

        // 활성 장치가 없을 때 이유 표시
        if !hasActiveSources && !recordingStore.isRecording {
            Text(midiManager.connectedSources.isEmpty
                 ? "MIDI 장치가 연결되지 않았습니다"
                 : "모든 MIDI 장치가 비활성화되었습니다")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Button("스튜디오 열기") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "studio")
        }
        .keyboardShortcut("o", modifiers: .command)

        Button("설정...") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("종료") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

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
        (Text(verbatim: "Impromptu — ") + Text(recordingStore.isRecording ? "menubar.title.recording" : "menubar.title.idle"))
            .foregroundStyle(.secondary)

        Divider()

        Button(recordingStore.isRecording ? "menubar.button.record_stop" : "menubar.button.record_start") {
            recordingStore.toggleRecording()
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(!hasActiveSources && !recordingStore.isRecording)

        // 활성 장치가 없을 때 이유 표시
        if !hasActiveSources && !recordingStore.isRecording {
            Text(midiManager.connectedSources.isEmpty
                 ? "menubar.status.no_device"
                 : "menubar.status.all_disabled")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Button("menubar.button.open_studio") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "studio")
        }
        .keyboardShortcut("o", modifiers: .command)

        Button("menubar.button.settings") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("menubar.button.quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

import SwiftUI

// MARK: - AppDelegate

/// LSUIElement(메뉴바 전용) 앱은 applicationIconImage를 자동 세팅하지 않음.
/// applicationDidFinishLaunching 시점에 명시적으로 지정해 NSAlert 계열
/// 다이얼로그(confirmationDialog 등)에 올바른 앱 아이콘이 표시되도록 한다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url  = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
}

// MARK: - App

@main
struct ImpromptuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var services = AppServices()

    var body: some Scene {
        MenuBarExtra {
            AppMenu()
                .environmentObject(services.midiManager)
                .environmentObject(services.recordingStore)
                .environmentObject(services.settings)
        } label: {
            Image(systemName: services.recordingStore.isRecording
                  ? "record.circle.fill"
                  : "music.note")
            .foregroundStyle(services.recordingStore.isRecording ? .red : .primary)
        }
        .menuBarExtraStyle(.menu)

        Window("app.window.studio", id: "studio") {
            StudioView()
                .environmentObject(services.midiManager)
                .environmentObject(services.recordingStore)
                .environmentObject(services.audioEngine)
                .environmentObject(services.midiPlayer)
                .environmentObject(services.settings)
        }
        .defaultSize(width: 480, height: 580)
        .windowResizability(.contentSize)

        Window("app.window.settings", id: "settings") {
            SettingsView()
                .environmentObject(services.midiManager)
                .environmentObject(services.audioEngine)
                .environmentObject(services.settings)
                .environmentObject(services.sfDownloader)
        }
        .defaultSize(width: 650, height: 450)
    }
}

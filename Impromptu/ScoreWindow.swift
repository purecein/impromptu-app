import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers

// MARK: - ScoreWebViewHolder

/// ScoreView → ScoreWindowContent 간 WKWebView 참조 및 창 참조 공유.
/// @Published webView는 makeNSView 후 set → PDF 버튼 활성 여부에 반영.
final class ScoreWebViewHolder: ObservableObject {
    @Published var webView: WKWebView?
    /// PDF 저장 패널의 부모 창으로 사용 (NSSavePanel.beginSheetModal)
    weak var window: NSWindow?
}

// MARK: - ScoreWindowManager

/// 레코딩 항목별로 악보 창을 하나씩 열거나 기존 창을 앞으로 가져옴.
/// 싱글턴 — 스튜디오 뷰에서 ScoreWindowManager.shared.open(item:) 으로 호출.
final class ScoreWindowManager {
    static let shared = ScoreWindowManager()
    private var openWindows: [UUID: NSWindowController] = [:]

    /// 항목에 대한 악보 창 열기. 이미 열려 있으면 포커스만.
    func open(item: RecordingItem) {
        if let existing = openWindows[item.id] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let holder = ScoreWebViewHolder()
        let itemID = item.id

        let content = ScoreWindowContent(item: item, holder: holder) { [weak self] in
            self?.openWindows[itemID]?.window?.close()
        }
        let hosting = NSHostingController(rootView: content)

        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "score.window.title")
        window.setContentSize(NSSize(width: 820, height: 262))
        window.minSize       = NSSize(width: 600, height: 262)
        window.styleMask     = [.titled, .closable, .resizable, .miniaturizable]
        window.setFrameAutosaveName("ScoreWindow")
        window.center()

        holder.window = window

        let controller = NSWindowController(window: window)
        openWindows[itemID] = controller

        // 창이 X 버튼으로 닫힐 때 딕셔너리에서 제거
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.openWindows.removeValue(forKey: itemID)
        }

        controller.showWindow(nil)
    }
}

// MARK: - ScoreWindowContent

/// 악보 창 내부 SwiftUI 뷰.
/// 상단: 파일명 + BPM + 악기명 / 중앙: ScoreView / 하단: [PDF 내보내기] [닫기]
struct ScoreWindowContent: View {
    let item:     RecordingItem
    @ObservedObject var holder: ScoreWebViewHolder
    let onClose:  () -> Void

    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            scoreArea
            Divider()
            footerRow
        }
        .frame(minWidth: 600, minHeight: 262)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let bpm = item.savedBPM {
                        Text("\(bpm) BPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !item.fileInfo.instrumentName.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.fileInfo.instrumentName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var scoreArea: some View {
        Group {
            if let url = item.savedURLs.first {
                ScoreView(url: url, onWebViewCreated: { wv in
                    DispatchQueue.main.async { holder.webView = wv }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("score.empty")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var footerRow: some View {
        HStack(spacing: 10) {
            Button {
                exportPDF()
            } label: {
                if isExporting {
                    Label("score.export.converting", systemImage: "arrow.down.document")
                } else {
                    Label("score.export.button", systemImage: "arrow.down.document")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isExporting || holder.webView == nil)

            if let err = exportError {
                Text(verbatim: err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            Button("score.button.close") { onClose() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - PDF Export

    private func exportPDF() {
        guard let webView = holder.webView else { return }
        isExporting = true
        exportError = nil

        // JS에서 SVG 실제 크기를 읽어 PDF rect 결정
        webView.evaluateJavaScript("""
            (function(){
                var svg = document.querySelector('#score svg');
                if (svg) {
                    var w = svg.width.baseVal.value;
                    var h = svg.height.baseVal.value;
                    return w + ',' + h;
                }
                return '800,140';
            })()
        """) { [self] result, _ in
            let size: CGSize
            if let str = result as? String {
                let parts = str.split(separator: ",").compactMap { Double($0) }
                size = CGSize(
                    width:  CGFloat(parts.first ?? 800) + 24,
                    height: CGFloat(parts.dropFirst().first ?? 140) + 24
                )
            } else {
                size = CGSize(width: 824, height: 164)
            }

            let config = WKPDFConfiguration()
            config.rect = CGRect(origin: .zero, size: size)

            webView.createPDF(configuration: config) { [self] pdfResult in
                DispatchQueue.main.async {
                    self.isExporting = false
                    switch pdfResult {
                    case .success(let data):
                        self.runSavePanel(data: data)
                    case .failure(let err):
                        self.exportError = String(format: String(localized: "score.export.error.convert"), err.localizedDescription)
                    }
                }
            }
        }
    }

    private func runSavePanel(data: Data) {
        let panel            = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true

        // 기본 파일명: 원본 .mid 파일명 → .pdf 확장자 변경
        let stem = item.savedURLs.first?.deletingPathExtension().lastPathComponent
            ?? item.displayName
        panel.nameFieldStringValue = "\(stem).pdf"

        let parentWindow = holder.window ?? NSApp.keyWindow
        let doSave = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
            } catch {
                DispatchQueue.main.async {
                    self.exportError = String(format: String(localized: "score.export.error.save"), error.localizedDescription)
                }
            }
        }

        if let pw = parentWindow {
            panel.beginSheetModal(for: pw, completionHandler: doSave)
        } else {
            panel.begin(completionHandler: doSave)
        }
    }
}

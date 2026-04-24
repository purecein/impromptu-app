import Foundation

// MARK: - 아카이브 타입

enum ArchiveType {
    /// 다운로드 파일 자체가 SF2
    case none
    /// ZIP 안에 SF2 포함 — 압축 해제 후 설치
    case zip
}

// MARK: - 카탈로그 항목

struct SoundFontCatalogEntry: Identifiable {
    /// AudioEngine SoundFont.id와 동일 — SF2 파일 스템(확장자 제외)
    let id:              String
    let displayName:     String
    let downloadURL:     URL
    /// 설치 후 점유 용량 (MB 단위, UI 표시용)
    let expectedSizeMB:  Int
    let fileName:        String     // 최종 저장 파일명 (예: "GeneralUserGS.sf2")
    var archiveType:     ArchiveType = .none
}

extension SoundFontCatalogEntry {
    static let catalog: [SoundFontCatalogEntry] = [
        // S. Christian Collins 공식 GitHub repo — 직접 SF2
        SoundFontCatalogEntry(
            id:             "GeneralUserGS",
            displayName:    "GeneralUser GS",
            downloadURL:    URL(string: "https://raw.githubusercontent.com/mrbumpy409/GeneralUser-GS/main/GeneralUser-GS.sf2")!,
            expectedSizeMB: 32,
            fileName:       "GeneralUserGS.sf2"
        ),
        // Salamander C5 Light — Google Drive ZIP (15 MB) → SF2 (25 MB)
        SoundFontCatalogEntry(
            id:             "SalamanderGrandPiano",
            displayName:    "Salamander Grand Piano",
            downloadURL:    URL(string: "https://drive.google.com/uc?export=download&id=0B5gPxvwx-I4KWjZ2SHZOLU42dHM")!,
            expectedSizeMB: 25,
            fileName:       "SalamanderGrandPiano.sf2",
            archiveType:    .zip
        ),
    ]
}

// MARK: - SoundFontDownloadManager

/// 카탈로그 항목을 순차적으로(한 번에 하나씩) 다운로드·삭제 관리.
final class SoundFontDownloadManager: NSObject, ObservableObject {

    // MARK: - 설치 경로

    static var installDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Impromptu/SoundFonts")
    }

    static func installedURL(for entry: SoundFontCatalogEntry) -> URL {
        installDirectory.appendingPathComponent(entry.fileName)
    }

    static func isInstalled(_ entry: SoundFontCatalogEntry) -> Bool {
        FileManager.default.fileExists(atPath: installedURL(for: entry).path)
    }

    // MARK: - Published 상태

    /// 현재 다운로드 중인 항목의 id. nil이면 유휴 상태.
    @Published private(set) var downloadingID: String? = nil
    /// 0.0 – 1.0 다운로드 진행률
    @Published private(set) var progress: Double = 0
    /// true이면 ZIP 압축 해제 진행 중 (downloadingID는 여전히 설정된 상태)
    @Published private(set) var isExtracting: Bool = false
    /// 설치된 항목 id 집합 — 파일 존재 여부 기반 (반응형 갱신)
    @Published private(set) var installedIDs: Set<String> = []
    @Published var errorMessage: String? = nil

    // MARK: - 콜백

    /// 다운로드(+압축 해제) 완료 시 메인 스레드에서 호출
    var onCompleted: ((SoundFontCatalogEntry) -> Void)?
    /// 삭제 완료 시 메인 스레드에서 호출
    var onDeleted: ((SoundFontCatalogEntry) -> Void)?

    // MARK: - 내부

    private var activeEntry: SoundFontCatalogEntry?
    private var downloadTask: URLSessionDownloadTask?
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()

    // MARK: - Init / Deinit

    override init() {
        super.init()
        refreshInstalledIDs()
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - Public API

    func startDownload(for entry: SoundFontCatalogEntry) {
        guard downloadingID == nil else { return }
        downloadingID = entry.id
        activeEntry   = entry
        progress      = 0
        errorMessage  = nil
        downloadTask  = session.downloadTask(with: entry.downloadURL)
        downloadTask?.resume()
        print("[Downloader] 시작: \(entry.displayName) — \(entry.downloadURL)")
    }

    func cancelDownload() {
        // 압축 해제 중에는 취소 불가 (Process를 중단하면 파일이 불완전 상태가 됨)
        guard !isExtracting else { return }
        downloadTask?.cancel()
        downloadTask = nil
        activeEntry  = nil
        DispatchQueue.main.async {
            self.downloadingID = nil
            self.progress      = 0
        }
        print("[Downloader] 취소됨")
    }

    func delete(_ entry: SoundFontCatalogEntry) {
        try? FileManager.default.removeItem(at: Self.installedURL(for: entry))
        installedIDs.remove(entry.id)
        print("[Downloader] 삭제됨: \(entry.displayName)")
        onDeleted?(entry)
    }

    /// 디스크 상태를 다시 확인해 installedIDs 갱신
    func refreshInstalledIDs() {
        installedIDs = Set(
            SoundFontCatalogEntry.catalog
                .filter { Self.isInstalled($0) }
                .map(\.id)
        )
    }

    // MARK: - 설치 헬퍼

    /// 직접 SF2: 다운로드 위치에서 설치 디렉토리로 이동
    private func directInstall(from location: URL, for entry: SoundFontCatalogEntry) {
        do {
            try FileManager.default.createDirectory(
                at: Self.installDirectory, withIntermediateDirectories: true)
            let dest = Self.installedURL(for: entry)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            print("[Downloader] 설치 완료: \(dest.path)")
            DispatchQueue.main.async {
                self.installedIDs.insert(entry.id)
                self.downloadingID = nil
                self.progress      = 1.0
                self.activeEntry   = nil
                self.onCompleted?(entry)
            }
        } catch {
            print("[Downloader] 설치 실패: \(error)")
            DispatchQueue.main.async {
                self.downloadingID = nil
                self.activeEntry   = nil
                self.errorMessage  = String(format: String(localized: "settings.soundfont.error.save"), error.localizedDescription)
            }
        }
    }

    /// ZIP: 임시 디렉토리에 압축 해제 후 SF2를 설치 디렉토리로 이동
    private func extractAndInstall(from archiveURL: URL, for entry: SoundFontCatalogEntry) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            defer {
                try? FileManager.default.removeItem(at: archiveURL)
                try? FileManager.default.removeItem(at: tempDir)
            }

            do {
                try FileManager.default.createDirectory(
                    at: tempDir, withIntermediateDirectories: true)

                // /usr/bin/unzip -o -q <archive> -d <tempDir>
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments     = ["-o", "-q", archiveURL.path, "-d", tempDir.path]
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    throw NSError(
                        domain: "Downloader", code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey:
                            String(format: String(localized: "settings.soundfont.error.extract_code"),
                                   process.terminationStatus)])
                }

                // tempDir 안에서 첫 번째 .sf2 파일 탐색
                guard let sf2URL = self.findSF2(in: tempDir) else {
                    throw NSError(
                        domain: "Downloader", code: -1,
                        userInfo: [NSLocalizedDescriptionKey:
                            String(localized: "settings.soundfont.error.sf2_not_found")])
                }

                try FileManager.default.createDirectory(
                    at: Self.installDirectory, withIntermediateDirectories: true)
                let dest = Self.installedURL(for: entry)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                // 같은 볼륨 내 이동이 아닐 수 있으므로 copy + remove
                try FileManager.default.copyItem(at: sf2URL, to: dest)
                print("[Downloader] 압축 해제 완료: \(dest.path)")

                DispatchQueue.main.async {
                    self.installedIDs.insert(entry.id)
                    self.downloadingID = nil
                    self.isExtracting  = false
                    self.progress      = 1.0
                    self.activeEntry   = nil
                    self.onCompleted?(entry)
                }
            } catch {
                print("[Downloader] 압축 해제 실패: \(error)")
                DispatchQueue.main.async {
                    self.downloadingID = nil
                    self.isExtracting  = false
                    self.activeEntry   = nil
                    self.errorMessage  = String(format: String(localized: "settings.soundfont.error.extract"), error.localizedDescription)
                }
            }
        }
    }

    /// 디렉토리를 재귀 탐색해 첫 번째 .sf2 파일 URL 반환
    private func findSF2(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator
            where url.pathExtension.lowercased() == "sf2" {
            return url
        }
        return nil
    }
}

// MARK: - URLSessionDownloadDelegate

extension SoundFontDownloadManager: URLSessionDownloadDelegate {

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let p = totalBytesExpectedToWrite > 0
            ? min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1.0)
            : 0
        DispatchQueue.main.async { self.progress = p }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let entry = activeEntry else { return }

        switch entry.archiveType {
        case .none:
            // 직접 SF2 — 그대로 이동
            directInstall(from: location, for: entry)

        case .zip:
            // ZIP — 임시 위치로 옮긴 뒤 비동기 압축 해제
            // (location은 delegate 반환 후 삭제되므로 반드시 먼저 이동)
            let archiveDest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".zip")
            do {
                try FileManager.default.moveItem(at: location, to: archiveDest)
            } catch {
                DispatchQueue.main.async {
                    self.downloadingID = nil
                    self.activeEntry   = nil
                    self.errorMessage  = String(format: String(localized: "settings.soundfont.error.temp_save"), error.localizedDescription)
                }
                return
            }
            DispatchQueue.main.async { self.isExtracting = true }
            extractAndInstall(from: archiveDest, for: entry)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        print("[Downloader] 오류: \(error)")
        DispatchQueue.main.async {
            self.downloadingID = nil
            self.activeEntry   = nil
            self.errorMessage  = error.localizedDescription
        }
    }
}

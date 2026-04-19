import Foundation

/// 사운드폰트 항목 — AudioEngine이 발견한 SF2/DLS 파일을 나타냄.
struct SoundFont: Identifiable, Equatable {
    /// 파일명 스템 (UserDefaults 저장 키로도 사용)
    let id: String
    /// UI에 표시될 이름
    let displayName: String
    let url: URL
    /// true이면 악기 선택 불가 (Salamander 등 단일 악기 전용 SF2)
    let isPianoOnly: Bool
}

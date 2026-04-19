# Impromptu

**즉흥 연주, 악상을 놓치지 마세요 — MIDI 키보드에서 바로 파일로.**

Impromptu는 macOS 메뉴바에 상주하는 경량 MIDI 레코더입니다. MIDI 키보드 연주를 녹음해 표준 MIDI 파일(`.mid`)로 저장하고, Logic Pro · Ableton · GarageBand 등 DAW에 바로 가져다 쓸 수 있습니다.

---

## 기능

- 🎹 **빠른 레코딩** — 메뉴바, 키보드 단축키, 또는 MIDI 컨트롤러의 물리 버튼으로 시작·종료 (MIDI Learn 지원)
- 💾 **표준 MIDI 파일** — SMF Format 0, 480 PPQN으로 저장. 모든 DAW와 완벽 호환
- 🎵 **앱 내 재생** — SF2 사운드폰트로 즉시 재생 확인
- 🎼 **악보 뷰어** — 녹음 파일을 악보로 미리보기 (VexFlow 렌더링, PDF 내보내기)
- 🎛️ **악기 · 사운드폰트 선택** — GM 128종 악기 지원. 앱 내 설정에서 GeneralUser GS 또는 Salamander Grand Piano 다운로드 가능
- ⚙️ **유연한 저장 방식** — 레코딩 종료 후 BPM 입력 다이얼로그, 또는 기본 BPM으로 자동 저장
- 🔇 **메뉴바 전용** — Dock 아이콘 없음. 필요할 때만 꺼내 쓰는 방해 없는 구조

---

## 스크린샷

> *준비 중*

---

## 요구 사항

| 항목 | 요구 사양 |
|---|---|
| macOS | 13 Ventura 이상 |
| 아키텍처 | Universal (Apple Silicon + Intel) |
| Xcode | 15 이상 |
| MIDI 기기 | USB 연결 클래스 컴플라이언트 MIDI 컨트롤러 |

---

## 빌드 방법

### 1. 저장소 클론

```bash
git clone https://github.com/purecein/impromptu-app.git
cd impromptu-app
```

### 2. Apple Developer Team ID 설정

로컬 설정 파일을 생성하고 본인의 Team ID를 입력합니다:

```bash
cp Local.xcconfig.template Local.xcconfig
```

`Local.xcconfig`를 열고 `YOUR_TEAM_ID_HERE`를 본인의 Team ID로 교체하세요.  
Team ID 확인: [developer.apple.com](https://developer.apple.com) → 계정 → 멤버십

### 3. 빌드

**Xcode:** `Impromptu.xcodeproj`를 열고 *Impromptu* 스킴 선택 후 `⌘B`

**커맨드라인 (코드 서명 있음):**

```bash
xcodebuild -scheme Impromptu -configuration Debug build \
  DEVELOPMENT_TEAM=$(grep DEVELOPMENT_TEAM Local.xcconfig | awk -F= '{print $2}' | tr -d ' ')
```

**커맨드라인 (코드 서명 없음 — CI 등):**

```bash
xcodebuild -scheme Impromptu -configuration Debug build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### 4. 테스트 실행

```bash
xcodebuild -scheme Impromptu -configuration Debug test \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

> **주의:** `Local.xcconfig`는 `.gitignore`에 포함되어 있으므로 커밋되지 않습니다.

### 5. pre-commit 훅 설치 (기여자 전용)

Xcode는 서명 설정을 변경할 때마다 `project.pbxproj`에 Team ID를 기록합니다. pre-commit 훅을 설치하면 커밋 직전에 자동으로 제거되어 저장소에 올라가지 않습니다.

```bash
cat > .git/hooks/pre-commit << 'EOF'
#!/usr/bin/env bash
PBXPROJ="Impromptu.xcodeproj/project.pbxproj"
if git diff --cached --name-only | grep -q "$PBXPROJ"; then
    if grep -q "DEVELOPMENT_TEAM = [^\"\"]*[^;]" "$PBXPROJ" 2>/dev/null; then
        sed -i '' 's/DEVELOPMENT_TEAM = [^;]*;/DEVELOPMENT_TEAM = "";/g' "$PBXPROJ"
        git add "$PBXPROJ"
        echo "ℹ️  pre-commit: DEVELOPMENT_TEAM을 project.pbxproj에서 제거했습니다."
    fi
fi
exit 0
EOF
chmod +x .git/hooks/pre-commit
```

---

## 사운드폰트

Impromptu는 사운드폰트를 번들에 포함하지 않습니다. **설정 → 사운드폰트** 탭에서 직접 다운로드하세요:

| 사운드폰트 | 용량 | 라이선스 | 특징 |
|---|---|---|---|
| **GeneralUser GS** | 약 30 MB | 무료, 상업 배포 가능 | GM 128종 악기 전체 포함 |
| **Salamander Grand Piano** | 약 800 MB | CC BY 3.0 | 고품질 그랜드 피아노 전용 |

사운드폰트가 설치되지 않은 경우 macOS 내장 DLS 신디사이저로 폴백 재생합니다 (음질 낮음).

---

## MIDI 트리거 설정 (MIDI Learn)

MIDI 컨트롤러의 어떤 CC 이벤트나 노트든 레코딩 시작·종료 트리거로 지정할 수 있습니다:

1. **설정 → MIDI** 탭 열기
2. *시작* 또는 *종료* 옆의 **감지** 버튼 클릭
3. 컨트롤러에서 원하는 버튼 또는 건반 누르기
4. CC/노트 번호가 자동으로 저장됨

장치별로, 시작과 종료를 서로 다른 버튼에 개별 지정할 수 있습니다.

---

## 아키텍처

```
CoreMIDI 입력
    └─▶ MIDIManager          — 패킷 파싱, 장치 핫플러그 감지
           └─▶ AppServices   — 라우팅 허브 (오디오 + 레코딩 + 트리거)
                  ├─▶ AudioEngine          — AVAudioUnitSampler (라이브 + 재생 이중 구조)
                  ├─▶ RecordingStore       — 이벤트 버퍼 → SMF 파일 (NSLock 스레드 안전)
                  └─▶ MIDIPlayer           — 백그라운드 Task 재생 스케줄러

SMF 파일
    └─▶ MIDIFileReader       — tick 이벤트·BPM·악기 메타 파싱
           └─▶ ScoreRenderer — MIDI tick → VexFlow JSON (5단계 파이프라인)
                  └─▶ ScoreView (WKWebView) — SVG 악보 렌더링
```

**주요 기술 결정사항:**

- **SMF Format 0** — 단일 트랙 병합으로 DAW 호환성 최우선
- **480 PPQN** — Logic Pro 기본 그리드 해상도와 동일
- **이중 AVAudioUnitSampler** — 라이브 입력용과 파일 재생용을 분리해 재생 중에도 라이브 악기 설정이 유지됨
- **양자화 이전 화음 그룹핑** — raw tick 공간(30 tick 임계값)에서 화음을 묶은 뒤 양자화 수행. 순서가 바뀌면 양자화 후 모든 onset이 120의 배수가 되어 화음 감지가 깨짐
- **VexFlow 4 UMD 번들** — WKWebView에서 `baseURL` 방식으로 로드. JSON은 Base64로 전달해 따옴표·이스케이프 문제 회피

---

## 기술 스택

| 구성 요소 | 기술 |
|---|---|
| 언어 | Swift 5 |
| UI | SwiftUI (macOS 13+) |
| MIDI I/O | CoreMIDI |
| 오디오 엔진 | AVFoundation — `AVAudioUnitSampler` |
| 악보 렌더링 | [VexFlow 4](https://www.vexflow.com) + WebKit |
| 설정 저장 | UserDefaults |
| 외부 패키지 | 없음 (Swift Package 미사용) |

---

## 프로젝트 구조

```
Impromptu/
├── ImpromptuApp.swift       # @main, MenuBarExtra + Window 씬 정의
├── AppServices.swift        # 전역 서비스 연결, MIDI 라우팅
│
├── MIDIEvent.swift          # MIDIEvent enum (noteOn/Off/CC/…)
├── MIDIManager.swift        # CoreMIDI 클라이언트, 패킷 파싱
├── MIDIFileWriter.swift     # SMF Format 0 바이너리 빌더
├── MIDIFileReader.swift     # SMF 파서
│
├── AudioEngine.swift        # 이중 AVAudioUnitSampler
├── MIDIPlayer.swift         # 파일 재생 스케줄러
├── SoundFont.swift          # SoundFont 모델
├── SoundFontDownloader.swift# SF2 다운로드 및 관리
├── InstrumentList.swift     # GM 악기 카탈로그
│
├── RecordingStore.swift     # 레코딩 상태, 파일 저장 흐름
├── RecordingItem.swift      # 레코딩 항목 모델 + 메타데이터
│
├── ScoreRenderer.swift      # MIDI tick → VexFlow JSON
├── ScoreView.swift          # WKWebView NSViewRepresentable
├── ScoreWindow.swift        # 레코딩별 NSWindow + PDF 내보내기
│
├── StudioView.swift         # 메인 스튜디오 창
├── SettingsView.swift       # 설정 창 (NavigationSplitView)
├── AppMenu.swift            # 메뉴바 드롭다운
├── BPMSaveSheet.swift       # BPM 입력 시트
└── SettingsStore.swift      # UserDefaults 기반 설정 저장소
```

---

## 라이선스

MIT License — 자세한 내용은 [LICENSE](LICENSE)를 참고하세요.

**서드파티 라이선스:**

- [VexFlow](https://github.com/0xfe/vexflow) — MIT License
- [GeneralUser GS](http://www.schristiancollins.com/generaluser.php) — 무료, 상업 배포 가능 (S. Christian Collins)
- [Salamander Grand Piano](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html) — CC BY 3.0 (Alexander Holm)

---

## 기여

버그 리포트나 Pull Request는 언제든 환영합니다. 큰 변경사항은 먼저 Issue를 열어 논의해 주세요.

빌드 시 반드시 본인의 `Local.xcconfig`를 생성하세요 ([빌드 방법](#빌드-방법) 참고). 이 파일은 gitignore에 포함되어 있으므로 커밋하지 않습니다.

---

*만든 사람: [Hojun Lee](mailto:purecein@gmail.com)*

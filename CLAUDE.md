# Impromptu — CLAUDE.md

macOS MenuBar MIDI 레코더 앱. CoreMIDI로 입력을 받아 SMF Format 0 파일로 저장하고,
AVAudioUnitSampler로 실시간 재생하며, WKWebView + VexFlow 4로 악보를 렌더링한다.

---

## 빌드 / 실행 명령어

```bash
# Debug 빌드 — 본인 Team ID를 환경변수로 전달
xcodebuild -scheme Impromptu -configuration Debug build \
  DEVELOPMENT_TEAM=$(cat Local.xcconfig | grep DEVELOPMENT_TEAM | awk -F= '{print $2}' | tr -d ' ')

# 코드 서명 없이 빌드 (CI / 서명 불필요한 경우)
xcodebuild -scheme Impromptu -configuration Debug build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Release 빌드
xcodebuild -scheme Impromptu -configuration Release build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# 단위 테스트 (ScoreRendererTests 등)
xcodebuild -scheme Impromptu -configuration Debug test \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# 앱 직접 실행 (빌드 후)
open /path/to/DerivedData/.../Impromptu.app
```

Xcode에서는 `⌘B` 빌드, `⌘R` 실행, `⌘U` 테스트.

> **코드 서명 설정 (최초 1회)**
> `Local.xcconfig.template`을 복사해 `Local.xcconfig`를 만들고 본인 Team ID를 입력.
> `Local.xcconfig`는 `.gitignore`에 포함되어 커밋되지 않음.

> **pre-commit 훅 설치 (최초 1회)**
> Xcode가 서명 설정 변경 시 `project.pbxproj`에 Team ID를 기록한다.
> 아래 명령으로 훅을 설치하면 커밋 직전에 자동으로 제거된다.
> `.git/` 디렉토리는 git이 추적하지 않으므로 클론 후 반드시 수동 설치 필요:
> ```bash
> cat > .git/hooks/pre-commit << 'EOF'
> #!/usr/bin/env bash
> PBXPROJ="Impromptu.xcodeproj/project.pbxproj"
> if git diff --cached --name-only | grep -q "$PBXPROJ"; then
>     if grep -q "DEVELOPMENT_TEAM = [^\"\"]*[^;]" "$PBXPROJ" 2>/dev/null; then
>         sed -i '' 's/DEVELOPMENT_TEAM = [^;]*;/DEVELOPMENT_TEAM = "";/g' "$PBXPROJ"
>         git add "$PBXPROJ"
>         echo "ℹ️  pre-commit: DEVELOPMENT_TEAM을 project.pbxproj에서 제거했습니다."
>     fi
> fi
> exit 0
> EOF
> chmod +x .git/hooks/pre-commit
> ```

---

## 프로젝트 개요 및 핵심 컨셉

- **MenuBar 앱** — `MenuBarExtra`로 메뉴바에 상주. 스튜디오 창(`studio`)과 설정 창(`settings`)은 `Window` Scene으로 별도 관리.
- **녹음**: CoreMIDI 패킷 수신 → `RecordingStore.addEvent()` → 메모리 버퍼 축적 → 레코딩 종료 시 SMF 파일 저장.
- **재생**: `MIDIPlayer`가 파일을 파싱하여 백그라운드 Task에서 스케줄링, `AudioEngine.playbackSampler`로 재생.
- **악보 뷰어**: `ScoreRenderer`가 MIDI tick 이벤트를 VexFlow JSON으로 변환, `ScoreView`(WKWebView)가 렌더링.
- **MIDI Learn**: 페달/버튼을 레코딩 시작·종료 트리거로 등록 가능.
- **사운드폰트**: 시스템 DLS 기본 제공, SF2 다운로드·관리 지원.

---

## 파일 구조와 역할

### 진입점 / 앱 생명주기

| 파일 | 역할 |
|------|------|
| `ImpromptuApp.swift` | `@main`, `MenuBarExtra` + `Window` Scene 정의, `AppServices` 소유 |
| `AppServices.swift` | 전역 서비스 소유·연결. CoreMIDI 이벤트를 AudioEngine → RecordingStore로 라우팅. MIDI Learn·트리거 로직 처리. `willTerminateNotification` 시 미저장 레코딩 폐기. |

### MIDI 처리

| 파일 | 역할 |
|------|------|
| `MIDIEvent.swift` | `enum MIDIEvent` — noteOn/noteOff/CC/pitchBend/aftertouch/programChange |
| `TimedMIDIEvent.swift` | `(event, hostTime, sourceName)` — CoreMIDI 타임스탬프 포함 이벤트 |
| `ScheduledMIDIEvent.swift` | `(event, absoluteTick)` — 파일 재생용 tick 기반 이벤트 |
| `MIDIManager.swift` | CoreMIDI 클라이언트. `MIDIInputPortCreateWithBlock`으로 패킷 파싱. PC(0xC0) 이벤트는 수신은 하되 `onMIDIEvent` 콜백에서 제외. `normalizedName()` — 장치 이름의 마지막 토큰 반환. |

### 녹음 / 저장

| 파일 | 역할 |
|------|------|
| `RecordingStore.swift` | 레코딩 상태 관리. NSLock으로 CoreMIDI 스레드 안전성 보장 (`recordingFlag = true`를 락 내부 마지막에 설정). 첫 이벤트 시 소스별 Program Change 주입. `SettingsStore.saveMode`에 따라 BPM 시트 또는 자동 저장. |
| `RecordingItem.swift` | 레코딩 항목 모델. `MIDIFileInfo`(instrumentName, soundFontName). `fromDisk(url:)` — 디스크에서 메타데이터 복원. |
| `MIDIFileWriter.swift` | SMF Format 0 바이너리 빌드. PPQN = 480. Meta 0x04 = 악기명, Meta 0x01 = SF2/DLS 태그. `buildSMFFromTicks()` — BPM 편집 시 원본 tick 이벤트 재활용. |
| `MIDIFileReader.swift` | SMF 파싱. `MIDIParseResult` — tickEvents, scheduledEvents, bpm, ppqn, durationSeconds. Meta 0x04 → `instrumentName`, Meta 0x01 prefix `"SF2:"/"DLS:System"` → `soundFontTag`. |

### 오디오 / 재생

| 파일 | 역할 |
|------|------|
| `AudioEngine.swift` | `AVAudioUnitSampler` 두 개: `sampler`(라이브 입력), `playbackSampler`(파일 재생 전용 — `@Published` 상태 건드리지 않음). `selectDLS()` / `setSoundFont(_:)`. `dlsIdentifier = "builtin_dls"`. |
| `MIDIPlayer.swift` | 파일 재생. 백그라운드 `Task` + `await MainActor.run`으로 `preparePlayback`. `stop()` 시 CC 123(All Notes Off)을 0–15 채널에 전송. |
| `SoundFont.swift` | `SoundFont` 모델. `isPianoOnly` 플래그. |
| `SoundFontDownloader.swift` | SF2 다운로드·삭제 관리. 완료 시 `AudioEngine.refreshSoundFonts()` 호출. |
| `InstrumentList.swift` | GM 악기 카테고리·프로그램 목록 정적 데이터. |

### 악보 뷰어

| 파일 | 역할 |
|------|------|
| `ScoreRenderer.swift` | `TickedMIDIEvent` → VexFlow JSON 변환. 5단계 파이프라인 (아래 참조). |
| `ScoreView.swift` | `NSViewRepresentable(WKWebView)`. HTML/JS 인라인 템플릿에 vexflow.js 로드. JSON은 base64 인코딩 후 `atob()`으로 전달. |
| `ScoreWindow.swift` | `ScoreWindowManager` 싱글턴 — 레코딩별 독립 `NSWindow`. `ScoreWindowContent` — 헤더/악보/PDF 내보내기 푸터. |

### UI

| 파일 | 역할 |
|------|------|
| `StudioView.swift` | 메인 스튜디오 창. 레코딩 버튼, 사운드폰트·악기 선택, 레코딩 목록(`RecordingRow`). |
| `SettingsView.swift` | 설정 창. 출력 장치, 저장 모드, MIDI 장치 활성화, MIDI Learn 트리거 설정. |
| `AppMenu.swift` | MenuBar 드롭다운 메뉴. 레코딩 토글, 창 열기 단축키. |
| `BPMSaveSheet.swift` | BPM 입력 시트 (저장/편집 공용). |
| `SettingsStore.swift` | `UserDefaults` 기반 앱 설정. `SaveMode`, `DeviceTriggers`, `LearningTarget`. |

---

## 주요 기술 결정사항

### SMF Format 0 / PPQN 480
- 모든 트랙을 단일 트랙에 병합하는 Format 0 사용.
- PPQN 고정값 480: 1 박자 = 480 ticks, 4/4 한 소절 = 1920 ticks, 16분음표 = 120 ticks.
- `MIDIFileWriter`와 `ScoreRenderer` 모두 이 값에 의존 — 변경 시 양쪽 동시 수정 필요.

### NSLock 스레드 안전성
- `RecordingStore.addEvent()`는 CoreMIDI 콜백 스레드에서 호출된다.
- `NSLock`으로 보호하며, `recordingFlag = true`는 반드시 락 내부 **마지막**에 설정 — 반쪽만 초기화된 상태를 addEvent가 보지 않도록.

### 이중 AVAudioUnitSampler
- `sampler`: 라이브 MIDI 입력 → 실시간 음원 출력.
- `playbackSampler`: 파일 재생 전용. `@Published` 프로퍼티를 절대 건드리지 않아 재생 중 UI 상태 변화 없음.
- `preparePlayback()` / `handlePlayback()` / `stopPlayback()` — playbackSampler 전용 API.

### ScoreRenderer 5단계 파이프라인
```
extractNotes   → noteOn/Off 쌍 → RawNote (startTick, duration, midiNote)
groupChords    → 원시 tick 공간에서 화음 묶기 (≤30 tick 임계값, 양자화 이전!)
quantizeGroups → onset → 16분음표 그리드 스냅, duration → 가장 가까운 표준 길이
buildMeasures  → 4/4 소절 분할 + 쉼표 삽입 (겹치는 음표 skip)
encodeMeasure  → MIDI 번호 → VexFlow key ("c#/4") + NoteSlot JSON
```
**핵심**: 화음 그룹핑은 **반드시 양자화 이전**에 수행해야 한다. 양자화 후에는 모든 onset이 120의 배수가 되어 30 tick 임계값이 무의미해진다 (예: 원본 10 tick 차이 → 양자화 후 120 tick 차이).

### VexFlow 4 번들 API 주의사항
- 번들: `vexflow.js` (~999 KB UMD), `Bundle.main.resourceURL`에서 로드.
- **`VF.Dot.buildAndAttach` 없음** — 이것은 VexFlow 3 API. 점음표는 `sn.addDotToAll()` 사용.
- `StaveNote` 생성자에 `dots:` 파라미터를 넘기면서 `addDotToAll()`도 호출하면 점이 2개가 된다. 생성자에는 넘기지 말 것.
- VexFlow key 이름에 반음계 위치 포함: `"c#/4"` (not `"c/4"`). Accidental 모디파이어도 별도로 추가해야 표시됨.
- JSON은 base64 인코딩 후 `atob()`로 JS에 전달 — 따옴표/이스케이프 문제 회피.

### ScoreWindowManager 싱글턴
- `[UUID: NSWindowController]` 딕셔너리로 레코딩별 창 하나씩 관리.
- `NSWindow.willCloseNotification` 옵저버로 X버튼 닫기 시 딕셔너리 정리.
- PDF 내보내기: JS로 `svg.width.baseVal.value` 조회 → `WKPDFConfiguration.rect` 설정 → `createPDF`.

### Program Change 주입
- 레코딩 시작 시 `audioEngine.currentProgram`을 캡처.
- 소스별 **첫 번째** 이벤트 수신 시 PC 이벤트를 `recordingStartTime`에 삽입.
- DAW 임포트 시 올바른 악기로 재생됨.

### Meta 이벤트 규약
- Meta 0x04: 악기명 (GM 프로그램 이름)
- Meta 0x01: 사운드폰트 태그 (`"SF2:displayName"` 또는 `"DLS:System"`)
- `MIDIFileReader`가 파싱하여 `RecordingItem.fileInfo`에 저장.

---

## 작업 시 주의사항

### ScoreRenderer 변경 시
- `ppqn`, `ticksPerMeasure`, `quantizeGridTicks` 상수는 `MIDIFileWriter.ppqn`과 항상 일치해야 한다.
- `groupChords`는 반드시 `quantizeGroups` **이전**에 호출. 순서 바꾸면 화음 감지 깨짐.
- `makeRests(from:to:)` 루프 조건은 `while remaining >= quantizeGridTicks` — 120 미만 잔여 tick은 버림.
- `largestFitting()` 반환값이 remaining보다 클 수 있음 (table.last 폴백) → `guard d.ticks <= remaining else { break }` 필수.

### 스레드 안전성
- `RecordingStore`의 `addEvent()`, `startRecording()`, `stopRecording()`은 CoreMIDI 스레드에서 호출될 수 있다.
- `NSLock` 범위 밖에서 `@Published` 프로퍼티를 읽거나 쓰지 말 것.
- `AudioEngine.preparePlayback()` — `@MainActor` 격리, `MIDIPlayer`에서 `await MainActor.run`으로 호출.

### UI 상태
- `playbackSampler`에 관련된 어떤 메서드도 `@Published` 상태를 변경해서는 안 된다. 재생 중 UI가 바뀌면 `sampler`(라이브) 설정이 풀릴 수 있다.
- `RecordingRow`에 버튼 순서: `[▶] [악보] [BPM] [Finder] [삭제]`.

### 사운드폰트
- DLS 식별자: `AudioEngine.dlsIdentifier = "builtin_dls"` — 하드코딩된 곳이 여러 군데. 변경 시 전체 검색 필요.
- `isPianoOnly` SF2는 악기 선택 Picker를 비활성화해야 함 — `StudioView`에서 처리 중.

### Xcode 프로젝트
- 새 `.swift` 파일 추가 시 `project.pbxproj`에 fileRef + buildFile UUID 쌍 등록 필요.
- UUID 패턴: fileRef `A1000001000000000000E6xx`, buildFile `A1000001000000000000E7xx` (xx는 파일별 고유값).
- `vexflow.js`는 Resources 빌드 페이즈에 포함되어야 함 (Copy Bundle Resources).

### 레코딩 저장 흐름
1. `stopRecording()` → pending 이벤트 플러시 → BPM 시트 표시 (`.dialog` 모드) 또는 자동 저장.
2. `savePending(bpm:)` → `MIDIFileWriter.build()` → 파일 저장 → `RecordingItem` 생성.
3. 저장 실패 시 `item.isSaved = false` → "미저장" 뱃지 표시 → 수동 재시도 가능.
4. 앱 종료(`willTerminateNotification`) 시 저장 안 된 레코딩은 `discardRecording()`으로 폐기.

---

## 의존성

- **CoreMIDI** — MIDI 장치 연결 및 패킷 수신
- **AVFoundation / AVAudioEngine** — 소프트웨어 신디사이저 (AVAudioUnitSampler)
- **WebKit** — VexFlow 악보 렌더링 (WKWebView)
- **VexFlow 4** (`vexflow.js`, ~999 KB) — SVG 악보 렌더링 라이브러리, 번들에 포함
- 외부 Swift 패키지 없음 (SPM 의존성 없음)

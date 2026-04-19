import Foundation

/// MIDI tick 이벤트 배열을 VexFlow 4 렌더링용 JSON 문자열로 변환하는 네임스페이스.
///
/// 가정:
///   - PPQN = 480 (MIDIFileWriter 고정값과 일치)
///   - 박자표: 4/4 고정 (1920 ticks / measure)
///   - 클레프: 트레블 고정
///
/// 처리 순서:
///   1. noteOn/noteOff 쌍 → RawNote 추출
///   2. 원시 tick 공간에서 화음 묶기 (양자화 이전, ≤30 tick 임계값)
///   3. 화음 그룹 단위로 양자화 (onset → 16분음표 그리드, duration → 가장 가까운 표준 길이)
///   4. 4/4 소절 단위 분할 + 쉼표 삽입 (겹치는 음표 건너뜀)
///   5. MIDI 번호 → VexFlow key ("c/4", "c#/4" …)
///   6. JSON 직렬화
///
/// 한계 (v1):
///   - 소절 경계를 넘는 음표는 시작 소절에만 표시 (타이 미구현)
///   - 겹치는 음표(이미 진행된 cursor 이전에 시작하는 음표)는 건너뜀
///   - 4/4 박자 고정
enum ScoreRenderer {

    // MARK: - Constants

    /// 화음 감지 임계값 (raw tick). 480 PPQN/120 BPM 기준 ≈ 31 ms.
    /// 사람이 연주한 화음의 타이밍 차이를 흡수하되, 빠른 패시지 음표(≥120 ticks)와 구분.
    private static let chordThresholdTicks: UInt32 = 30

    private static let ppqn:             UInt32 = 480
    private static let ticksPerMeasure:  UInt32 = 1920   // 4/4 × 480
    private static let quantizeGridTicks: UInt32 = 120   // 16th note

    // MARK: - Duration table

    private struct Dur {
        let ticks: UInt32
        let base:  String   // VexFlow 기본 문자열: "w","h","q","8","16"
        let dots:  Int      // 0 또는 1
    }

    /// 길이 내림차순 — greedy 쉼표 채우기에서 가장 큰 값부터 시도
    private static let table: [Dur] = [
        Dur(ticks: 1920, base: "w",  dots: 0),
        Dur(ticks: 1440, base: "h",  dots: 1),
        Dur(ticks:  960, base: "h",  dots: 0),
        Dur(ticks:  720, base: "q",  dots: 1),
        Dur(ticks:  480, base: "q",  dots: 0),
        Dur(ticks:  360, base: "8",  dots: 1),
        Dur(ticks:  240, base: "8",  dots: 0),
        Dur(ticks:  120, base: "16", dots: 0),
    ]

    // MARK: - JSON data model (Encodable)

    private struct ScoreJSON: Encodable {
        let bpm:      Int
        let measures: [Measure]

        struct Measure: Encodable {
            let notes: [NoteSlot]
        }

        struct NoteSlot: Encodable {
            let keys:        [String]
            let duration:    String    // VexFlow 기본 + "r" 접미사(쉼표) 예: "q", "qr"
            let dots:        Int
            let isRest:      Bool
            let accidentals: [String?] // nil → 임시표 없음
        }
    }

    // MARK: - Public API

    /// TickedMIDIEvent 배열과 BPM으로 VexFlow JSON 문자열 반환.
    /// 파싱/인코딩 실패 시 빈 measures JSON 반환.
    static func buildJSON(events: [TickedMIDIEvent], bpm: Int) -> String {
        let raw      = extractNotes(from: events)
        let chords   = groupChords(from: raw)       // 양자화 이전 화음 묶기
        let qChords  = quantizeGroups(chords)       // 그룹 단위 양자화
        let measures = buildMeasures(from: qChords) // 소절 분할 + 쉼표

        let scoreObj = ScoreJSON(bpm: bpm, measures: measures.map(encodeMeasure))
        let encoder  = JSONEncoder()
        guard let data = try? encoder.encode(scoreObj),
              let str  = String(data: data, encoding: .utf8) else {
            return "{\"bpm\":\(bpm),\"measures\":[]}"
        }
        return str
    }

    // MARK: - Step 1: Note pair extraction

    private struct RawNote {
        let startTick: UInt32
        let duration:  UInt32
        let midiNote:  UInt8
    }

    private static func extractNotes(from events: [TickedMIDIEvent]) -> [RawNote] {
        var pending: [UInt8: UInt32] = [:]  // note → startTick
        var result:  [RawNote]       = []

        for e in events {
            switch e.event {
            case .noteOn(_, let note, let vel) where vel > 0:
                pending[note] = e.absoluteTick

            case .noteOn(_, let note, _), .noteOff(_, let note):
                if let start = pending.removeValue(forKey: note) {
                    // 최소 16분음표(120 ticks)를 보장해 너무 짧은 음표를 안정적으로 스냅
                    let dur = e.absoluteTick > start
                        ? max(e.absoluteTick - start, quantizeGridTicks)
                        : quantizeGridTicks
                    result.append(RawNote(startTick: start, duration: dur, midiNote: note))
                }

            default:
                break
            }
        }

        // 닫히지 않은 noteOn → 4분음표 길이로 마감
        for (note, start) in pending {
            result.append(RawNote(startTick: start, duration: ppqn, midiNote: note))
        }

        return result.sorted { $0.startTick < $1.startTick }
    }

    // MARK: - Step 2: Chord grouping (raw tick space, BEFORE quantization)
    //
    // 핵심: 양자화 이전에 화음을 묶어야 한다.
    // 양자화 후 모든 onset이 120의 배수가 되면 ≤20 tick 임계값이 무용해진다.
    // 예) 55 tick → 0, 65 tick → 120 (실제 10 tick 차이인데 양자화 후 120 차이)
    //
    // 정렬된 notes에 대해 sliding window 방식 적용:
    // 마지막 그룹의 start tick 기준으로 ≤chordThresholdTicks 이면 같은 화음.

    private struct RawChordGroup {
        let start:   UInt32
        let maxDur:  UInt32
        let notes:   [UInt8]
    }

    private static func groupChords(from notes: [RawNote]) -> [RawChordGroup] {
        var groups: [RawChordGroup] = []
        for raw in notes {   // notes는 startTick 오름차순 정렬
            if var last = groups.last,
               raw.startTick - last.start <= chordThresholdTicks {
                // 마지막 그룹과 합치기
                last = RawChordGroup(
                    start:  last.start,
                    maxDur: max(last.maxDur, raw.duration),
                    notes:  last.notes + [raw.midiNote]
                )
                groups[groups.count - 1] = last
            } else {
                groups.append(RawChordGroup(start: raw.startTick,
                                            maxDur: raw.duration,
                                            notes:  [raw.midiNote]))
            }
        }
        return groups
    }

    // MARK: - Step 3: Quantization helpers

    private static func quantizeTick(_ t: UInt32) -> UInt32 {
        ((t + quantizeGridTicks / 2) / quantizeGridTicks) * quantizeGridTicks
    }

    /// 주어진 tick 수에 가장 가까운 Dur 반환 (table 비어있으면 16분음표)
    private static func nearestDur(_ ticks: UInt32) -> Dur {
        table.min(by: { abs(Int($0.ticks) - Int(ticks)) < abs(Int($1.ticks) - Int(ticks)) })
            ?? table.last!
    }

    /// remaining 이하에서 가장 큰 Dur 반환 (greedy 쉼표 채우기용)
    private static func largestFitting(_ remaining: UInt32) -> Dur {
        // remaining이 최소 grid(120)보다 작으면 16분음표로 고정 후 호출측에서 guard 처리
        table.first(where: { $0.ticks <= remaining }) ?? table.last!
    }

    private struct QuantizedGroup {
        let start: UInt32
        let dur:   UInt32
        let notes: [UInt8]
    }

    private static func quantizeGroups(_ groups: [RawChordGroup]) -> [QuantizedGroup] {
        groups
            .map { g in
                QuantizedGroup(
                    start: quantizeTick(g.start),
                    dur:   nearestDur(g.maxDur).ticks,
                    notes: g.notes
                )
            }
            .sorted { $0.start < $1.start }
    }

    // MARK: - Step 4: Measure splitting + rest filling

    private struct BeatSlot {
        let dur:       Dur
        let midiNotes: [UInt8]  // 비어 있으면 쉼표
    }

    private static func buildMeasures(from groups: [QuantizedGroup]) -> [[BeatSlot]] {
        guard !groups.isEmpty else { return [] }

        let maxEnd      = groups.map { $0.start + $0.dur }.max() ?? 0
        let numMeasures = max(1, Int((maxEnd + ticksPerMeasure - 1) / ticksPerMeasure))
        var measures: [[BeatSlot]] = []

        for m in 0..<numMeasures {
            let mStart = UInt32(m) * ticksPerMeasure
            let mEnd   = mStart + ticksPerMeasure

            let inM = groups.filter { $0.start >= mStart && $0.start < mEnd }

            var slots:  [BeatSlot] = []
            var cursor: UInt32     = mStart

            for g in inM {
                // 이미 진행된 cursor 이전 onset이면 건너뜀 (sustained note overlap)
                guard g.start >= cursor else { continue }

                // onset 앞 쉼표
                if g.start > cursor {
                    slots += makeRests(from: cursor, to: g.start)
                    cursor = g.start
                }

                // 소절 경계를 넘지 않는 duration 선택
                let remaining = mEnd - g.start
                let proposed  = nearestDur(min(g.dur, remaining))
                let chosen    = proposed.ticks <= remaining ? proposed : largestFitting(remaining)

                slots.append(BeatSlot(dur: chosen, midiNotes: g.notes.sorted()))
                cursor = g.start + chosen.ticks
            }

            // 소절 끝 쉼표
            if cursor < mEnd {
                slots += makeRests(from: cursor, to: mEnd)
            }

            measures.append(slots)
        }

        return measures
    }

    /// `from`부터 `to`까지의 tick 갭을 greedy하게 쉼표 BeatSlot으로 채운다.
    /// from == to이면 빈 배열 반환. from과 to는 모두 quantizeGridTicks의 배수여야 한다.
    private static func makeRests(from start: UInt32, to end: UInt32) -> [BeatSlot] {
        guard end > start else { return [] }
        var remaining = end - start
        var result: [BeatSlot] = []
        while remaining >= quantizeGridTicks {
            let d = largestFitting(remaining)
            // largestFitting이 remaining보다 큰 값을 반환하는 경우 방어
            guard d.ticks <= remaining else { break }
            result.append(BeatSlot(dur: d, midiNotes: []))
            remaining -= d.ticks
        }
        return result
    }

    // MARK: - Step 5: MIDI note → VexFlow key

    // pitch class → (VexFlow key 이름, 임시표 기호 또는 nil)
    //
    // VexFlow 저수준 API에서 key 이름은 반음계적 staff 위치를 결정하고,
    // Accidental 모디파이어는 임시표 기호를 화면에 표시한다. 둘 다 필요.
    // 예: C#4 → key="c#/4" + addModifier(Accidental('#'))
    private static let pcInfo: [(name: String, acc: String?)] = [
        ("c",  nil), ("c#", "#"), ("d",  nil), ("d#", "#"), ("e",  nil),
        ("f",  nil), ("f#", "#"), ("g",  nil), ("g#", "#"), ("a",  nil), ("a#", "#"), ("b",  nil)
    ]

    private static func vfKey(_ midi: UInt8) -> (key: String, acc: String?) {
        let pc     = Int(midi) % 12
        let octave = Int(midi) / 12 - 1
        return ("\(pcInfo[pc].name)/\(octave)", pcInfo[pc].acc)
    }

    // MARK: - Step 6: Encode to ScoreJSON.Measure

    private static func encodeMeasure(_ slots: [BeatSlot]) -> ScoreJSON.Measure {
        let noteSlots: [ScoreJSON.NoteSlot] = slots.map { slot in
            if slot.midiNotes.isEmpty {
                // 쉼표: 트레블 클레프 B4 위치 (VexFlow가 standard rest position으로 이동)
                return ScoreJSON.NoteSlot(
                    keys:        ["b/4"],
                    duration:    slot.dur.base + "r",
                    dots:        slot.dur.dots,
                    isRest:      true,
                    accidentals: [nil]
                )
            } else {
                let pairs = slot.midiNotes.map { vfKey($0) }
                return ScoreJSON.NoteSlot(
                    keys:        pairs.map(\.key),
                    duration:    slot.dur.base,
                    dots:        slot.dur.dots,
                    isRest:      false,
                    accidentals: pairs.map(\.acc)
                )
            }
        }
        return ScoreJSON.Measure(notes: noteSlots)
    }
}

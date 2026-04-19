import SwiftUI

/// 레코딩 저장 또는 BPM 편집 시 표시되는 시트.
struct BPMSaveSheet: View {
    let title: String
    let onSave: (Int) -> Void
    let onCancel: () -> Void

    @State private var bpmText: String

    init(
        title: String = "레코딩 저장",
        initialBPM: Int = 120,
        onSave: @escaping (Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title    = title
        self.onSave   = onSave
        self.onCancel = onCancel
        self._bpmText = State(initialValue: String(initialBPM))
    }

    private var bpmValue: Int? {
        guard let n = Int(bpmText), (20...300).contains(n) else { return nil }
        return n
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.title2.bold())

            Text("BPM을 입력하면 DAW에서\n그리드에 맞게 열립니다")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.subheadline)

            TextField("BPM", text: $bpmText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .multilineTextAlignment(.center)
                .onSubmit { if let bpm = bpmValue { onSave(bpm) } }

            HStack(spacing: 12) {
                Button("취소", role: .cancel) { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("저장") { if let bpm = bpmValue { onSave(bpm) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(bpmValue == nil)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(30)
        .frame(width: 280)
    }
}

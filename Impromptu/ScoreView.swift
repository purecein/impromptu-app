import SwiftUI
import WebKit

/// MIDI 파일 악보를 VexFlow SVG로 렌더링하는 macOS 뷰.
///
/// WKWebView를 NSViewRepresentable로 래핑.
/// 번들의 vexflow.js를 baseURL 로드 방식으로 사용하며,
/// ScoreRenderer가 생성한 JSON을 base64 인코딩 후 JS에 전달.
/// 악보가 긴 경우 수평 스크롤 가능.
///
/// 사용 예:
///   ScoreView(url: someURL)
///   ScoreView(url: someURL, onWebViewCreated: { wv in holder.webView = wv })
struct ScoreView: NSViewRepresentable {

    let events: [TickedMIDIEvent]
    let bpm:    Int

    /// 생성된 WKWebView 참조를 외부에 전달하는 콜백 (PDF 내보내기 등에 활용)
    var onWebViewCreated: ((WKWebView) -> Void)? = nil

    // MARK: - Convenience inits

    /// 저장된 MIDI 파일 URL에서 직접 생성
    init(url: URL, onWebViewCreated: ((WKWebView) -> Void)? = nil) {
        let parsed  = try? MIDIFileReader.parse(url: url)
        self.events = parsed?.tickEvents ?? []
        self.bpm    = parsed?.bpm ?? 120
        self.onWebViewCreated = onWebViewCreated
    }

    /// 이미 파싱된 이벤트 배열로 생성
    init(events: [TickedMIDIEvent], bpm: Int, onWebViewCreated: ((WKWebView) -> Void)? = nil) {
        self.events = events
        self.bpm    = bpm
        self.onWebViewCreated = onWebViewCreated
    }

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        // 라이트 모드 강제 (SVG 색상 일관성)
        webView.appearance = NSAppearance(named: .aqua)

        // HTML 로드 — vexflow.js는 번들 리소스에서 읽음
        let baseURL = Bundle.main.resourceURL
        webView.loadHTMLString(Self.htmlTemplate, baseURL: baseURL)

        // JSON은 didFinish 후 렌더링 — Coordinator에 큐잉
        context.coordinator.pendingJSON = ScoreRenderer.buildJSON(events: events, bpm: bpm)

        // 참조 전달
        onWebViewCreated?(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let json = ScoreRenderer.buildJSON(events: events, bpm: bpm)
        guard json != context.coordinator.lastRenderedJSON else { return }
        context.coordinator.lastRenderedJSON = json

        if context.coordinator.isLoaded {
            context.coordinator.render(json, in: webView)
        } else {
            context.coordinator.pendingJSON = json
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var isLoaded          = false
        var pendingJSON:      String?
        var lastRenderedJSON: String?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            if let json = pendingJSON {
                render(json, in: webView)
                pendingJSON = nil
            }
        }

        func render(_ json: String, in webView: WKWebView) {
            guard let data = json.data(using: .utf8) else { return }
            let b64 = data.base64EncodedString()
            // atob()으로 복원 후 renderScore() 호출
            webView.evaluateJavaScript("renderScore(atob('\(b64)'))") { _, _ in }
        }
    }

    // MARK: - HTML template

    /// 번들의 vexflow.js를 로드하고 renderScore(jsonStr) 함수를 노출하는 HTML.
    /// body 높이를 100%로 지정해 WKWebView 크기에 맞게 늘어남.
    /// 악보 SVG 폭이 가로를 초과하면 수평 스크롤 활성화.
    static let htmlTemplate: String = """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        html, body { height: 100%; min-height: 140px; background: #ffffff; }
        body { padding: 4px 8px; overflow-x: auto; overflow-y: hidden; }
        #score { display: inline-block; }
        #score svg { display: block; }
        #err { color: #c00; font: 11px/1.4 monospace; padding: 4px;
               white-space: pre-wrap; max-width: 500px; }
      </style>
    </head>
    <body>
      <div id="score"></div>
      <div id="err"></div>
      <script src="vexflow.js"></script>
      <script>
    function renderScore(jsonStr) {
      var errDiv = document.getElementById('err');
      errDiv.textContent = '';
      try {
        var data     = JSON.parse(jsonStr);
        var VF       = Vex.Flow;
        var measures = data.measures || [];
        var div      = document.getElementById('score');
        div.innerHTML = '';

        if (measures.length === 0) {
          div.innerHTML = '<p style="color:#aaa;padding:12px;font:12px sans-serif">음표 없음</p>';
          return;
        }

        // 레이아웃 계산 — 첫 소절은 클레프+박자표 포함으로 넓게
        var FIRST_W = 290;
        var OTHER_W = 200;
        var H       = 128;
        var totalW  = FIRST_W + Math.max(0, measures.length - 1) * OTHER_W + 20;

        var renderer = new VF.Renderer(div, VF.Renderer.Backends.SVG);
        renderer.resize(totalW, H);
        var ctx = renderer.getContext();

        var x = 10;
        measures.forEach(function(measure, mi) {
          var isFirst = (mi === 0);
          var w       = isFirst ? FIRST_W : OTHER_W;

          var stave = new VF.Stave(x, 12, w - 10);
          if (isFirst) { stave.addClef('treble').addTimeSignature('4/4'); }
          stave.setContext(ctx).draw();

          var noteObjs = (measure.notes || []).map(function(n) {
            // dots는 constructor에 넘기지 않는다.
            // constructor의 dots: N 과 addDotToAll() 을 동시에 쓰면
            // addDot() 내부에서 this.dots++ 가 중복 호출되어 이중점이 된다.
            var sn = new VF.StaveNote({
              clef:     'treble',
              keys:     n.keys,
              duration: n.duration
            });

            // 임시표
            if (VF.Accidental && Array.isArray(n.accidentals)) {
              n.accidentals.forEach(function(acc, i) {
                if (acc) { sn.addModifier(new VF.Accidental(acc), i); }
              });
            }

            // 점음표 — VexFlow 4 번들 API: StaveNote.addDotToAll()
            // (VF.Dot.buildAndAttach 는 이 빌드에 존재하지 않음)
            if (n.dots && n.dots > 0) {
              sn.addDotToAll();
            }

            return sn;
          });

          if (noteObjs.length > 0) {
            var voice = new VF.Voice({ num_beats: 4, beat_value: 4 }).setStrict(false);
            voice.addTickables(noteObjs);
            var innerW = w - (isFirst ? 95 : 25);
            new VF.Formatter().joinVoices([voice]).format([voice], innerW);
            voice.draw(ctx, stave);
          }

          x += w;
        });
      } catch(e) {
        errDiv.textContent = 'ScoreView error: ' + e.message;
        console.error(e);
      }
    }
    window.renderScore = renderScore;
      </script>
    </body>
    </html>
    """
}

# Impromptu

**Capture musical ideas instantly — straight from your MIDI keyboard to a file.**

[한국어 README](README.ko.md)

Impromptu is a lightweight macOS menu bar app that records your MIDI keyboard input and saves it as a standard MIDI file (`.mid`), ready to drag into Logic Pro, Ableton, or any DAW.

---

## Features

- 🎹 **One-tap recording** — Start and stop from the menu bar, keyboard shortcut, or a physical button on your MIDI controller (MIDI Learn supported)
- 💾 **Standard MIDI files** — Saves as SMF Format 0 at 480 PPQN, fully compatible with any DAW
- 🎵 **In-app playback** — Listen back immediately using SF2 soundfonts
- 🎼 **Score viewer** — Preview recordings as sheet music (VexFlow rendering, PDF export)
- 🎛️ **Instrument & soundfont selection** — All 128 GM instruments; download GeneralUser GS or Salamander Grand Piano from within the app
- ⚙️ **Flexible save options** — Prompt for BPM after recording, or auto-save with a default BPM
- 🔇 **Menu bar only** — No Dock icon; stays out of your way until you need it

---

## Screenshots

> *Screenshots coming soon*

---

## Requirements

| Item | Requirement |
|---|---|
| macOS | 13 Ventura or later |
| Architecture | Universal (Apple Silicon + Intel) |
| Xcode | 15 or later |
| MIDI device | Any class-compliant USB MIDI controller |

---

## Building from Source

### 1. Clone the repository

```bash
git clone https://github.com/purecein/impromptu-app.git
cd impromptu-app
```

### 2. Set up your Apple Developer Team ID

Copy the config template and fill in your own Team ID:

```bash
cp Local.xcconfig.template Local.xcconfig
```

Open `Local.xcconfig` and replace `YOUR_TEAM_ID_HERE` with your Team ID.
You can find your Team ID at [developer.apple.com](https://developer.apple.com) → Account → Membership.

### 3. Build

**In Xcode:** Open `Impromptu.xcodeproj`, select the *Impromptu* scheme, and press `⌘B`.

**Command line (with signing):**

```bash
xcodebuild -scheme Impromptu -configuration Debug build \
  DEVELOPMENT_TEAM=$(grep DEVELOPMENT_TEAM Local.xcconfig | awk -F= '{print $2}' | tr -d ' ')
```

**Command line (without code signing):**

```bash
xcodebuild -scheme Impromptu -configuration Debug build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### 4. Run tests

```bash
xcodebuild -scheme Impromptu -configuration Debug test \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

> **Note:** `Local.xcconfig` is listed in `.gitignore` and will never be committed.

### 5. Install the pre-commit hook (contributors only)

Xcode writes your Team ID back into `project.pbxproj` whenever you change signing settings. The pre-commit hook strips it automatically before every commit so it never reaches the repository.

```bash
cat > .git/hooks/pre-commit << 'EOF'
#!/usr/bin/env bash
PBXPROJ="Impromptu.xcodeproj/project.pbxproj"
if git diff --cached --name-only | grep -q "$PBXPROJ"; then
    if grep -q "DEVELOPMENT_TEAM = [^\"\"]*[^;]" "$PBXPROJ" 2>/dev/null; then
        sed -i '' 's/DEVELOPMENT_TEAM = [^;]*;/DEVELOPMENT_TEAM = "";/g' "$PBXPROJ"
        git add "$PBXPROJ"
        echo "ℹ️  pre-commit: DEVELOPMENT_TEAM stripped from project.pbxproj"
    fi
fi
exit 0
EOF
chmod +x .git/hooks/pre-commit
```

---

## Soundfonts

Impromptu does not bundle a soundfont. Download one from **Settings → Soundfonts**:

| Soundfont | Size | License | Best for |
|---|---|---|---|
| **GeneralUser GS** | ~30 MB | Free, commercial use OK | All 128 GM instruments |
| **Salamander Grand Piano** | ~800 MB | CC BY 3.0 | High-quality piano only |

If no soundfont is installed, the app falls back to the macOS built-in DLS synthesizer (lower quality).

---

## MIDI Trigger Setup (MIDI Learn)

Any CC event or note from a MIDI controller can trigger recording start/stop:

1. Open **Settings → MIDI**
2. Click **감지 (Learn)** next to *Start* or *Stop*
3. Press the button or key on your controller
4. The CC/note number is saved automatically

Start and stop can be mapped to different buttons per device.

---

## Architecture

```
CoreMIDI input
    └─▶ MIDIManager          — packet parsing, device hot-plug
           └─▶ AppServices   — routing hub (audio + recording + triggers)
                  ├─▶ AudioEngine          — AVAudioUnitSampler (live + playback)
                  ├─▶ RecordingStore       — event buffer → SMF file (NSLock thread-safe)
                  └─▶ MIDIPlayer           — background Task playback scheduler

SMF file
    └─▶ MIDIFileReader       — parse tick events, BPM, instrument meta
           └─▶ ScoreRenderer — MIDI ticks → VexFlow JSON (5-step pipeline)
                  └─▶ ScoreView (WKWebView) — SVG sheet music rendering
```

**Key technical decisions:**

- **SMF Format 0** — single-track merge for maximum DAW compatibility
- **480 PPQN** — matches Logic Pro's default grid resolution
- **Dual AVAudioUnitSampler** — separate instances for live input and file playback so playback never disrupts live instrument settings
- **Chord grouping before quantization** — groups simultaneous notes within a 30-tick window in raw tick space; doing this after quantization would break detection since all onsets become multiples of 120 ticks
- **VexFlow 4 UMD bundle** — loaded via `WKWebView` with `baseURL`; JSON transferred as Base64 to avoid quote-escaping issues

---

## Tech Stack

| Component | Technology |
|---|---|
| Language | Swift 5 |
| UI | SwiftUI (macOS 13+) |
| MIDI I/O | CoreMIDI |
| Audio engine | AVFoundation — `AVAudioUnitSampler` |
| Score rendering | [VexFlow 4](https://www.vexflow.com) + WebKit |
| Persistence | UserDefaults |
| External dependencies | None (no Swift packages) |

---

## Project Structure

```
Impromptu/
├── ImpromptuApp.swift       # @main, MenuBarExtra + Window scenes
├── AppServices.swift        # Global service wiring, MIDI routing
│
├── MIDIEvent.swift          # MIDIEvent enum (noteOn/Off/CC/…)
├── MIDIManager.swift        # CoreMIDI client, packet parsing
├── MIDIFileWriter.swift     # SMF Format 0 binary builder
├── MIDIFileReader.swift     # SMF parser
│
├── AudioEngine.swift        # Dual AVAudioUnitSampler
├── MIDIPlayer.swift         # File playback scheduler
├── SoundFont.swift          # SoundFont model
├── SoundFontDownloader.swift# SF2 download & management
├── InstrumentList.swift     # GM instrument catalog
│
├── RecordingStore.swift     # Recording state, file save flow
├── RecordingItem.swift      # Recording item model + metadata
│
├── ScoreRenderer.swift      # MIDI ticks → VexFlow JSON
├── ScoreView.swift          # WKWebView NSViewRepresentable
├── ScoreWindow.swift        # Per-recording NSWindow + PDF export
│
├── StudioView.swift         # Main studio window
├── SettingsView.swift       # Settings (NavigationSplitView)
├── AppMenu.swift            # Menu bar dropdown
├── BPMSaveSheet.swift       # BPM input sheet
└── SettingsStore.swift      # UserDefaults-backed settings
```

---

## License

MIT License — see [LICENSE](LICENSE) for details.

**Third-party:**

- [VexFlow](https://github.com/0xfe/vexflow) — MIT License
- [GeneralUser GS](http://www.schristiancollins.com/generaluser.php) — Free for commercial use (S. Christian Collins)
- [Salamander Grand Piano](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html) — CC BY 3.0 (Alexander Holm)

---

## Contributing

Bug reports and pull requests are welcome. For major changes, please open an issue first to discuss what you'd like to change.

When building, make sure to create your own `Local.xcconfig` (see [Building from Source](#building-from-source)) — this file is gitignored and must not be committed.

---

*Made by [Hojun Lee](mailto:purecein@gmail.com)*

# LiveFlow

A menu-bar push-to-talk dictation app for macOS. Hold **Fn**, speak, and a
borderless overlay shows your words as you say them. Release **Fn** and LiveFlow
pastes clean, punctuated text into whatever app is in front.

It is a small, native, on-device alternative to tools like Wispr Flow — no
account, no network, no dock icon. About 950 lines of Swift, built with `swiftc`
directly (no Xcode project required).

## How it works

LiveFlow uses **two speech recognizers on purpose**:

- **Live overlay** — Apple's classic `SFSpeechRecognizer` streams partial results
  with almost no latency, so the on-screen pill updates as fast as you talk. It is
  rough, but it is instant.
- **Final text** — while you dictate, the raw microphone audio is also written to
  a temporary `.caf` file. On release, that file is re-run through macOS 26's
  newer `SpeechAnalyzer` / `SpeechTranscriber` for a slower but noticeably more
  accurate pass. That result is what gets pasted.

Everything runs on-device (`requiresOnDeviceRecognition`); audio never leaves the
machine, and the temp recording is deleted as soon as the accurate pass finishes.

### The Cleaner

Raw dictation is messy, so committed text goes through a small cleanup pass
(`Cleaner` in `Sources/TranscriptModel.swift`):

- Strips fillers (`um`, `uh`, `erm`, …).
- Fixes the recognizer's habit of capitalizing opportunistically after pauses
  (e.g. `the Shows Above Every thing`) — it capitalizes only at real sentence
  starts, while preserving `I`, acronyms, proper names, and known technical terms.
- Normalizes technical aliases (`vest tool` → `VESC Tool`, `bamboo studio` →
  `Bambu Studio`, `usb c` → `USB-C`, and so on).

### Custom vocabulary

`~/LiveFlow/vocabulary.txt` biases recognition toward terms you use often. Add one
phrase per line; changes take effect on the next dictation without rebuilding. The
repo ships a default list of maker/hardware terms (VESC, ESP32-C3, Shapr3D, Bambu
Lab, …). Open it any time from the menu-bar **Open Custom Vocabulary** item.

### Live coloring

Words in the overlay are colored by part of speech (nouns, verbs, adjectives, …)
using `NLTagger`. Token IDs are derived from position + text rather than random
UUIDs, so already-spoken words stay put instead of re-animating on every partial
result.

## Requirements

- **macOS 14+** for the live overlay and dictation.
- **macOS 26+** for the high-accuracy final pass (older systems fall back to the
  live transcript).
- Apple Silicon.

## Permissions

On first launch LiveFlow requests:

- **Microphone** and **Speech Recognition** — to hear and transcribe you.
- **Accessibility** — required for the global **Fn** key monitor and for the
  synthetic ⌘V auto-paste. Grant it under *System Settings → Privacy & Security →
  Accessibility*. Without it, LiveFlow still works from the menu-bar **Start
  Dictation** item and copies to the clipboard, but Fn push-to-talk and auto-paste
  are disabled.

## Build

```bash
./build.sh
```

This compiles `Sources/*.swift` into `build/LiveFlow.app` and code-signs it. Set
`LIVEFLOW_SIGN_ID` to sign with your own identity:

```bash
LIVEFLOW_SIGN_ID="Apple Development: Your Name (XXXXXXXXXX)" ./build.sh
```

A stable signing identity matters here: macOS ties TCC permission grants
(Accessibility, Microphone) to the app's code signature, so re-signing with the
same identity keeps your granted permissions across rebuilds.

## Usage

- Hold **Fn** to dictate; release to paste.
- Or use the menu-bar icon: **Start Dictation**, **Copy Last Transcript**, **Open
  Transcript History**, **Open Custom Vocabulary**, **Text Size**.
- Every finished dictation is appended to `~/LiveFlow/transcripts.md`.

## Project layout

| File | Role |
| --- | --- |
| `Sources/AppDelegate.swift` | Menu-bar app, permissions, auto-paste |
| `Sources/Transcriber.swift` | Dual-recognizer pipeline (live + accurate pass) |
| `Sources/TranscriptModel.swift` | Token model, POS tagging, the Cleaner |
| `Sources/Overlay.swift` | Borderless, click-through SwiftUI overlay pill |
| `Sources/FnKey.swift` | Fn push-to-talk monitor |
| `Sources/Vocabulary.swift` | Contextual terms + alias normalization |
| `Sources/History.swift` | Appends transcripts to a markdown log |

## License

MIT — see [LICENSE](LICENSE).

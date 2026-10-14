# Plan

The Flutter port of `../pdfreader`, Android first. Decisions are in
[adr/0001-flutter-port.md](adr/0001-flutter-port.md).

Each step ends with a check that shows it works. "Device" means the owner's phone over USB, with
`flutter run` or `integration_test`, plus a note of what was seen. Without a phone a step is
reported as **not verified on device**. Work stops after each milestone for the owner's review.

Every step that adds logic writes the test first. A port of a TypeScript test keeps its name, its
inputs and its expected outputs.

## M0: toolchain and an empty app

**Done 2026-10-15.** Flutter 3.47.7, Dart 3.13.5, Android SDK 36, phone SM-G780G (Android 13)
listed by `adb devices`. App ID `io.github.jjomin.pdfreader`. `tool/check.ps1` passes, and fails
at the test stage when a test is broken. The debug APK built from the path with a space in it
(first Gradle build 192 s, it fetched NDK r28c and SDK Platform 36) and showed the template app
on the phone. Visual Studio is not installed; `flutter doctor` flags it, which only matters for
Windows desktop builds, not for Android or `tool/dump.dart`.

| # | Step | Done when |
| --- | --- | --- |
| 0.1 | The owner installs Flutter, Android Studio's SDK and platform tools, and connects the phone (steps in the Phase 0 report). | `flutter doctor -v` has no Android errors and `adb devices` lists the phone as `device`. |
| 0.2 | `flutter create --platforms android,ios --org <owner's choice> .` in this folder. Add `CLAUDE.md` (commands, layout, the raw-range idea, offline only, the rules), `analysis_options.yaml` with strict typing, `.gitignore` with `models/`. | `flutter analyze` and `flutter test` pass. `flutter run` shows the template app on the phone. |
| 0.3 | `tool/check.ps1`: analyze, `dart format --set-exit-if-changed`, unit tests. The equivalent of `npm run check`. | It passes, and fails when a test is broken on purpose. |

## M1: the core on Android

### Pure logic, ported (`lib/shared/`, no Flutter imports)

| # | Step | Done when |
| --- | --- | --- |
| 1.1 | `types.dart`: `RawItem`, `RawRange`, `Word`, `Utterance`, `WordTiming`, `VoiceRef`, `Lang`, `Role`. Plain immutable classes, no code generation. | It compiles, and `flutter test` runs. |
| 1.2 | `segment.dart`: UAX #29 sentence and word boundaries with `isWordLike`. `tool/gen_unicode.dart` writes the property tables. `tool/segmenter_golden.mjs` writes `test/golden/segments.json` from Node's `Intl.Segmenter`. | Unicode's `SentenceBreakTest.txt` and `WordBreakTest.txt` pass, apart from documented ICU differences, and every golden case matches. |
| 1.3 | `layout.dart`: `layoutPage`, `rawRanges`, `blockSpans`, `readableText`, with NFKC from `unorm_dart`. Port `layout.test.ts` and the `blockSpans` part of `search.test.ts`. | All 8 layout cases and the `blockSpans` case pass. |
| 1.4 | `language.dart` and `utterances.dart`. Port `utterances.test.ts`. | All 8 cases pass, including the colon split and the quote roles. |
| 1.5 | `align.dart` (`alignWords`, `estimateTimings`) and `settings.dart` (speed, voices, `resolveVoice`; reading settings and progress come with it because it is one file). Port `align.test.ts` and `settings.test.ts`. | All 5 align cases and all settings cases pass. |
| 1.6 | `pdfium_text.dart`: PDFium's `fullText` and `charRects` to `RawItem`s plus the raw-offset to char-index map (ADR 1). Unit tests on hand-made char streams: line ends, inserted spaces, a ligature, a rotated run. Then `tool/dump.dart file.pdf [n]` (on Windows, through `pdfrx_engine`) prints what would be spoken, like `npm run dump`. | Unit tests pass. `dart run tool/dump.dart` on the desktop's `tests/fixtures/sample.pdf` gives the same sentences, languages and roles as the desktop's dump. Differences are listed, and any missed heading decides whether the font upgrade in ADR 1 is needed. |

### On the phone

| # | Step | Done when |
| --- | --- | --- |
| 1.7 | Open a PDF: `DocumentAccess` platform channel (Kotlin, system picker, read bytes). `PdfViewer` from pdfrx with pinch zoom and scrolling. | Device: `sample.pdf` and one real paper open from the picker, pinch zoom is smooth, text is sharp at 300 %. |
| 1.8 | **Speech spike.** `tool/push_models.ps1` copies the models to the phone. Load Piper Thorsten, Kokoro and the recogniser with `sherpa_onnx`, synthesise one German and one English sentence, and run the recogniser on each. | Device: both sentences are heard. Recorded in the ADR: load time per model, time per second of audio, memory used, recogniser output. **Stop here and report if Kokoro is slower than about 0.8 seconds per second of audio**, because then the two-sentence lookahead cannot keep up. |
| 1.9 | Speech service in its own isolate: `synthesize(text, words, lang, voice, speed)` returns samples and word timings (recogniser, else the estimate). Two sentences prepared ahead, like `reader.ts`. | A unit test with a fake engine covers the queue: order, cancellation on seek, lookahead of two. Device: a page is spoken without gaps longer than at sentence joins. |
| 1.10 | Playback: play, pause, stop, previous and next sentence, speed (0.6 to 2). Language per sentence and voice per language and role through `resolveVoice`. "Models missing" screen. | Device: a German page with an English sentence switches voice and back. Each control does what it says. Without models the app opens PDFs and names the missing folders. |
| 1.11 | Highlighting: the spoken sentence tinted, the spoken word marked, both painted from raw ranges through the char-index map onto `charRects`, in pdfrx's per-page paint callback. The view follows the voice unless the user scrolled in the last three seconds. | Device: the tint and the word mark sit on the right letters on `sample.pdf` at 100 % and 300 %, including a word broken across lines. The view follows onto the next page. |
| 1.12 | Screen off: `audio_service` with a media notification and lock-screen controls (play, pause, previous, next). | Device: reading goes on for two minutes with the screen off, the notification controls work, and the highlight is in the right place when the screen comes back. |
| 1.13 | `integration_test/reader_test.dart`: opens the fixture, plays, checks that the spoken sentence advances and the word ranges lie inside it. | It passes on the phone with `flutter test integration_test`. |
| 1.14 | `docs/SPEC.md` for the port: what works, known limits (with the measured numbers from 1.8), APK size. | Written. **Stop for review.** |

## M2: marks and comments

| # | Step | Done when |
| --- | --- | --- |
| 2.1 | Decide where notes are written on Android (open question 3 in the Phase 0 report). Extend `DocumentAccess` accordingly. | The owner has chosen. A note file can be written and read back next to a PDF on the phone. |
| 2.2 | `notes.dart`: `parseNotes`, `reanchor`, `sortAnnotations`, `toMarkdown`, and an encoder that writes what `JSON.stringify(notes, null, 2)` writes: same key order, two-space indent, no newline at the end. Port `notes.test.ts`. A new whitespace-tolerant fallback in `reanchor`, with its own tests. | All ported cases pass. A golden test: a file written by the desktop, parsed and written again, is byte for byte the same. |
| 2.3 | Selection to raw range: pdfrx's text selection gives char indices, mapped back through the char-index map. A mark cannot span two pages, as on the desktop. | Unit test for the map. Device: selecting a phrase shows the menu. |
| 2.4 | Marks: highlight, underline, strikethrough in four colours, painted per kind and colour. The kind stays selected for the next mark. | Device: all twelve combinations appear on the right letters, also where marks overlap. |
| 2.5 | Comments on a mark, general notes, tap a mark to open its comment. Saved automatically. | Device: comments survive closing and reopening the app. |
| 2.6 | Interchange. A notes file made by the desktop for `sample.pdf` opened on the phone, and one made on the phone opened on the desktop by the owner. | Recorded: how many marks are found in each direction. None is lost from the file. **Stop for review.** |

## M3: search and the reading view

| # | Step | Done when |
| --- | --- | --- |
| 3.1 | `search.dart`: `findInBlocks`. Port the rest of `search.test.ts`. | All cases pass, including a phrase across a hyphenated line break. |
| 3.2 | `TextView` interface in Dart (raw ranges to screen and back), with the PDF pages as its first implementation. Speech, marks and search move onto it. | No change visible on the device. The integration test still passes. |
| 3.3 | Search UI: every match marked, next and previous, clear. | Device: "representation" is found across a line break in `sample.pdf` or a real paper. |
| 3.4 | Reading view: the blocks as restyled text, the second `TextView`. Font, size, line spacing, letter spacing, light, sepia and dark. Bundled fonts: OpenDyslexic and Lexend (OFL). Verdana, Comic Sans MS, Arial and Georgia are Microsoft fonts and cannot be bundled; open question 6 in the Phase 0 report. | Device: speech, word mark, marks and search all work in the reading view. Switching views keeps the place and the voice keeps reading. Settings are remembered. **Stop for review.** |

## M4: place, export, annotated PDF

| # | Step | Done when |
| --- | --- | --- |
| 4.1 | Remember the place per file: view, zoom, page and offset, the last sentence. Keyed by the document's URI, not a path. Port the progress cases of `settings.test.ts` if not done in 1.5. | Device: closing and reopening a paper returns to the same page and sentence, and Play continues from it. |
| 4.2 | Markdown export through the system "save as" picker. | Device: the file opens and matches `toMarkdown`'s unit test format. |
| 4.3 | **Spike, then decide:** writing marks as standard PDF annotations into a copy. pdfrx's own editing API, or PDFium's `FPDFPage_CreateAnnot` with quad points, colour, contents and an appearance stream. A short ADR if a new package is needed. | The owner has approved the approach. |
| 4.4 | "Save PDF" with every mark and its comment, general notes as a sticky note on page one. | The saved copy shows the marks in pdfrx on the phone and in the desktop app (PDF.js), checked by the owner. **Stop for review.** |

## Not planned

The XTTS GPU voice, the Windows installer and Pocket TTS (out of scope). Supertonic 3, focus
mode, softened sentence edges and an in-app model import are possible later steps, not part of
these milestones.

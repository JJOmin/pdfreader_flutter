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

**Status 2026-10-15: steps 1.1 to 1.7 done, 1.8 measured and stopped at its limit.**

- 1.1 to 1.5: the shared logic is ported with its tests (108 tests pass with `tool/check.ps1`).
  The segmenter passes all 1,944 word and 512 sentence cases of Unicode 17's tests and all 58
  golden cases from Node's Intl.Segmenter, with no exceptions needed.
- 1.6: `tool/dump.dart` gives the desktop's output on `sample.pdf` exactly. On a real paper the
  differences are the font-based headings, recorded in ADR 1 section 1. `--runs` prints the
  text runs for debugging. PDFium's line-end hyphen (U+0002) is handled.
- 1.7: device: `sample.pdf` opens through the system picker and renders. **Not verified on
  device:** pinch zoom smoothness and sharpness at 300 % (adb cannot pinch); checked in 1.11.
- 1.8: device: both voices speak and the recogniser hears every word, but Kokoro needs 0.84 to
  0.91 s per second of audio on a long sentence, over the limit. Numbers in ADR 1.
- **Decided 2026-10-21 (ADR 2):** for now the phone has no voice of its own. It plays only audio the
  desktop prepared. Steps 1.9 and 1.10 were rewritten for that. The 1.8 code and `sherpa_onnx`
  stay in the repository unused. Removing them, which would shrink the APK, is a later decision.

- **2026-10-21: 5.2 and 1.9 to 1.13 done**, read from a library pushed over USB. 145 unit tests
  pass. On the phone, the integration test reads `sample.pdf` as the desktop prepared it: every
  word of each sentence gets the mark, and the mark stays inside the tinted sentence. Next,
  previous and pause work. **Left for the owner on the device:** 1.11 at 300 % zoom, and 1.12 for
  two minutes with the screen off and the notification's buttons (tested: 20 s with the screen
  off, the phone dozing, reading went on). A sentence join takes about
  300 ms on the phone, against 80 ms on the desktop: the player reports a sentence's end 200 to
  280 ms after its audio length. Details and limits in [SPEC.md](SPEC.md).

**Order from here (the owner, 2026-10-21, after M1's review):**

1. **Wi-Fi sync:** 5.3 to 5.6, with the desktop's S5 and S6. Step 5.6 needs 4.1, so 4.1 comes
   just before it.
2. **The reading view on the phone:** 3.2 (the `TextView` interface), then 3.4. The phone's PDF
   is hard to read on a small screen, so this comes before marks. Search (3.1, 3.3) after it.
3. **Marks:** M2, then 5.7, which syncs them both ways with the desktop, merged per mark.
4. **Nextcloud and Dropbox:** M6, the phone's half of the desktop's ADR 8, which is accepted and
   whose desktop half is built (its step S7). It starts with this repository's ADR 3.

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
| 1.9 | Speech from a prepared library (ADR 2 section 1). `tool/push_library.ps1` copies a library folder from the desktop to the app's storage over USB. A page whose words agree with the index (count and hash) is read with the index's sentences, mapped to raw ranges by word index. Any other page falls back to the sync key, and a sentence with no match is skipped. Two sentences are prepared ahead, like `reader.ts`. | Unit tests: word index to raw range, including a word broken across lines; the fallback on a page whose words differ; and, with a fake library, the queue's order, cancellation on seek, lookahead of two, and skipping a sentence with no match. Device: a page of the pushed fixture is spoken without gaps longer than at sentence joins. |
| 1.10 | Playback with `just_audio`: play, pause, stop, previous and next sentence, speed 0.6 to 2 through `setSpeed`, keeping the pitch. A sentence with no audio is skipped. A document with no prepared library opens and shows "Not prepared on the desktop", and Play is off. | Device: each control does what it says, and speed 1.5 keeps the pitch. A sentence removed from an index by hand is skipped. A PDF opened from the picker shows "Not prepared on the desktop". |
| 1.11 | Highlighting: the spoken sentence tinted, the spoken word marked, both painted from raw ranges through the char-index map onto `charRects`, in pdfrx's per-page paint callback. The view follows the voice unless the user scrolled in the last three seconds. | Device: the tint and the word mark sit on the right letters on `sample.pdf` at 100 % and 300 %, including a word broken across lines. The view follows onto the next page. |
| 1.12 | Screen off: `audio_service` with a media notification and lock-screen controls (play, pause, previous, next). | Device: reading goes on for two minutes with the screen off, the notification controls work, and the highlight is in the right place when the screen comes back. |
| 1.13 | `integration_test/reader_test.dart`: opens the fixture, plays, checks that the spoken sentence advances and the word ranges lie inside it. | It passes on the phone with `flutter test integration_test`. |
| 1.14 | `docs/SPEC.md` for the port: what works, known limits (with the measured numbers from 1.8), APK size. | Written. **Stop for review.** |

## M2: marks and comments

| # | Step | Done when |
| --- | --- | --- |
| 2.1 | **Done 2026-10-21.** The owner chose the app's own storage: `lib/notes_store.dart` keeps one file per document in `notes/<docId>.json`, named by the PDF's hash, the id the library uses. Written beside the file and renamed over it. Decide where notes are written on Android (open question 3 in the Phase 0 report). Extend `DocumentAccess` accordingly. | The owner has chosen. A note file can be written and read back next to a PDF on the phone. |
| 2.2 | **Done 2026-10-21.** 9 tests, and `test/golden/notes.json`, written by the desktop's `JSON.stringify(notes, null, 2)` with control characters, emoji and U+2028, round-trips byte for byte. `lib/shared/notes.dart`: `parseNotes`, `reanchor`, `sortAnnotations`, `toMarkdown`, and an encoder that writes what `JSON.stringify(notes, null, 2)` writes: same key order, two-space indent, no newline at the end. Port `notes.test.ts`. A new whitespace-tolerant fallback in `reanchor`, with its own tests. | All ported cases pass. A golden test: a file written by the desktop, parsed and written again, is byte for byte the same. |
| 2.3 | **Done 2026-10-21**, but not as written: pdfrx selects in its reading-order text (`loadStructuredText`), whose characters are numbered differently from PDFium's char stream (`loadText`) that the raw string is made from, so the char-index map does not apply. The selection is placed by its glyph boxes: left and right edges equal, and the line decides between glyphs at the same x (`rawRangeFromBoxes`, 6 tests). Device: a long press selects a word and shows the menu, and the mark holds exactly the word. A selection that spans two pages gives one mark per page. Selection to raw range: pdfrx's text selection gives char indices, mapped back through the char-index map. A mark cannot span two pages, as on the desktop. | Unit test for the map. Device: selecting a phrase shows the menu. |
| 2.4 | **Done 2026-10-21.** Device (`integration_test/marks_test.dart`, screenshots): all twelve kinds and colours on the right words, with an overlapping strike-through over a fill and an underline, in the pages and in the reading view. The kind stays selected for the next mark. Colours are the desktop's, so the voice is blue and search orange. Marks: highlight, underline, strikethrough in four colours, painted per kind and colour. The kind stays selected for the next mark. | Device: all twelve combinations appear on the right letters, also where marks overlap. |
| 2.5 | **Done 2026-10-21.** Device: a tap on a mark opens its comment, in both views; typing is saved within half a second; the Notes button lists every mark by page with the general notes; the marks were all there after leaving and reopening. Comments on a mark, general notes, tap a mark to open its comment. Saved automatically. | Device: comments survive closing and reopening the app. |
| 2.6 | **Done 2026-10-21 for the file; not yet seen by the owner in the desktop app.** `test/interchange_test.dart` and the desktop's reanchor on `sample.pdf` and the 7-page paper, with a mark over every fifth sentence: the phone finds 5 of 5 and 73 of 73 of the desktop's; the desktop found only **21 of 72** of the phone's, because its reanchor had no whitespace tolerance. Fixed there (commit `0773be6`, with tests): now 5 of 5 and 72 of 72. Interchange. A notes file made by the desktop for `sample.pdf` opened on the phone, and one made on the phone opened on the desktop by the owner. | Recorded: how many marks are found in each direction. None is lost from the file. **Stop for review.** |

## M3: search and the reading view

| # | Step | Done when |
| --- | --- | --- |
| 3.1 | **Done 2026-10-21.** 3 ported cases pass. `search.dart`: `findInBlocks`. Port the rest of `search.test.ts`. | All cases pass, including a phrase across a hyphenated line break. |
| 3.2 | **Done 2026-10-21.** `lib/views/text_view.dart`. The views share a list of highlights (page, raw ranges, kind) that each paints its own way, since Flutter has no shared highlight layer like the desktop's CSS. Raw ranges back from the screen come with marks (M2). The page opens the PDF once (`PdfDocumentRefDirect`) for both views and the speech. `TextView` interface in Dart (raw ranges to screen and back), with the PDF pages as its first implementation. Speech, marks and search move onto it. | No change visible on the device. The integration test still passes. |
| 3.3 | **Done 2026-10-21.** Device: "Silbentrennung" found once across the hyphenated line break and shown on page 2; "Spalte" four times, next and previous step through them. Search UI: every match marked, next and previous, clear. | Device: "representation" is found across a line break in `sample.pdf` or a real paper. |
| 3.4 | **Done 2026-10-21**, without marks, which come with M2. Device (`integration_test/reading_view_test.dart`, screenshots): the word mark moves in the reading view, switching views keeps the page while the voice goes on, OpenDyslexic on dark applies and is kept in `settings.json`, and the document reopens in the reading view. Fonts: OpenDyslexic and Lexend turned from the desktop's @fontsource WOFF files into TTF by `tool/woff_to_ttf.dart`; the Microsoft fonts map to the phone's own sans and serif. Reading view: the blocks as restyled text, the second `TextView`. Font, size, line spacing, letter spacing, light, sepia and dark. Bundled fonts: OpenDyslexic and Lexend (OFL). Verdana, Comic Sans MS, Arial and Georgia are Microsoft fonts and cannot be bundled; open question 6 in the Phase 0 report. | Device: speech, word mark, marks and search all work in the reading view. Switching views keeps the place and the voice keeps reading. Settings are remembered. **Stop for review.** |

## M4: place, export, annotated PDF

| # | Step | Done when |
| --- | --- | --- |
| 4.1 | **Done 2026-10-21**, brought forward for 5.6. `lib/places.dart` keeps `progress.json` and `settings.json` (the speed) in the desktop's formats; the viewer opens on the saved page through pdfrx's `initialPageNumber`, because a move during its first layout is undone. Device (`integration_test/place_test.dart`, PHASE=place): reopened on page 2, and Play went on at the sentence read last. Remember the place per file: view, zoom, page and offset, the last sentence. Keyed by the document's URI, not a path. Port the progress cases of `settings.test.ts` if not done in 1.5. | Device: closing and reopening a paper returns to the same page and sentence, and Play continues from it. |
| 4.2 | Markdown export through the system "save as" picker. | Device: the file opens and matches `toMarkdown`'s unit test format. |
| 4.3 | **Spike, then decide:** writing marks as standard PDF annotations into a copy. pdfrx's own editing API, or PDFium's `FPDFPage_CreateAnnot` with quad points, colour, contents and an appearance stream. A short ADR if a new package is needed. | The owner has approved the approach. |
| 4.4 | "Save PDF" with every mark and its comment, general notes as a sticky note on page one. | The saved copy shows the marks in pdfrx on the phone and in the desktop app (PDF.js), checked by the owner. **Stop for review.** |

## M5: audio and place from the desktop

Decided in ADR 2 and the desktop's ADR 7, both accepted on 2026-10-21. Built before M2, in the
order given under M1. Step 5.6 needs 4.1, so 4.1 is done first. The desktop's steps S2 to S6 are in
its `docs/SPEC.md`. They are built in that repository, never from here.

| # | Step | Done when |
| --- | --- | --- |
| 5.1 | **Done 2026-10-21.** Sentences matched 100 % on `sample.pdf` and 92.6 % on the paper, with identical words page by page. The owner chose to take the desktop's sentence breaks by word index (ADR 2, "Measured"). Open: one real German paper. **Spike, on the PC.** Print the sentences of `sample.pdf` and two real papers with the desktop's `npm run dump` and with `tool/dump.dart`. Compare their sync keys (desktop ADR 7 section 3). | Recorded in ADR 2: per file, the share of the phone's sentences whose key is among the desktop's, and the kind of difference behind each miss. **Stop and report if it is below about 98 %** on a real paper. The phone has no voice to fall back on, so every miss is a sentence that is not read. |
| 5.2 | **Done 2026-10-21.** `test/sync_golden_test.dart` reads both PDFs with PDFium on the PC: every page's words and hash equal the desktop's golden files. `lib/shared/sync.dart`: a page's words and their hash, the sync key, and parsing the manifest, a page index and a state file. Port the desktop's tests for them (desktop S2). | All ported cases pass. The page words and hash of `sample.pdf` and the paper equal the desktop's, checked by a golden file the desktop writes. |
| 5.3 | **Done 2026-10-21.** `integration_test/desktop_sync_test.dart` against the running desktop: heard after 2.2 s on the owner's Wi-Fi, a wrong code refused with nothing sent (the desktop was asked once), paired after Accept. `lib/shared/pairing.dart` (7 tests), `lib/desktop_link.dart`, `lib/desktops_page.dart`, the `pdfreader/discovery` channel. Discovery and pairing: the `Discovery` platform channel (`MulticastLock`), the "Desktops" screen with the announced desktops and a typed address, the code entry, the certificate pin and the stored token. Needs desktop S5. | Device: the desktop appears in the list. A wrong code is refused before anything is sent. After Accept on the desktop, the app reconnects with its token after a restart. |
| 5.4 | **Done 2026-10-21**, except Remove on the device (it deletes the folder). The first sync fetched 21 files, 0.3 MB, adding up to the manifest's `bytes`; the second fetched nothing. `lib/shared/download_plan.dart` (3 tests). Download: the desktop's library, then a document's PDF, manifest, indexes and missing audio into the app's storage. Show progress and a Remove action. Fetch again only what is missing. | Device: the fixture downloads, each file's size equals the desktop's, and a second sync fetches nothing. Remove frees the space. |
| 5.5 | **Done 2026-10-21.** After the library was deleted on the phone and fetched by sync, `reader_test.dart` read it: every word marked in all 5 sentences. Read what was downloaded: downloaded documents open from the app's storage through the same path as the pushed library of 1.9. | Device: a document downloaded in 5.4, not pushed, is read with the word mark on the right words. |
| 5.6 | **Done 2026-10-21.** Device, both ways, against the running desktop: the phone's place reached it by sync and it offered "Continue where you stopped on Galaxy S20 FE, page 2?"; the desktop's place came back and the phone offered "…on Leos_PC, page 1?" and went there. Place: write `state/<device>.json`, send it on every sync, and offer the newest other device's place when a document opens. | Device: read to page 2 on the phone and sync. The desktop then offers page 2 at that sentence. The other way round works as well. **Stop for review.** |
| 5.7 | **Notes both ways.** `notes.json` joins the library (desktop step S9). The phone sends its notes with `PUT` and fetches the desktop's. Merged per mark, as the owner chose on 2026-10-21 (desktop ADR 7 section 1): marks are kept by id from both sides, an edited mark takes the newer edit, a deleted mark stays deleted (a tombstone), and the general notes take the newer text. `lib/shared/notes_merge.dart` with tests, the same cases as the desktop's. | Unit tests for the merge: new on both sides, edited on both, deleted on one and edited on the other. Device: a mark made on the phone shows on the desktop after a sync, and one made on the desktop shows on the phone. Neither is lost when both changed before the sync. **Stop for review.** |

## Not planned

The XTTS GPU voice, the Windows installer and Pocket TTS (out of scope). Supertonic 3, focus
mode, softened sentence edges and an in-app model import are possible later steps, not part of
these milestones.

## M6: Nextcloud and Dropbox (the phone's half of desktop ADR 8)

Accepted for the desktop on 2026-10-21 in `../pdfreader/docs/adr/0008-sync-through-a-store.md`,
and built there (its step S7): the same library as ADR 7, encrypted (AES-256-GCM, a key the user
enters on every device), in the user's own Nextcloud (WebDAV, Login Flow v2) or Dropbox (App
folder, OAuth with PKCE). ADR 8 asks for this repository's own ADR before the phone's side is built.
The offline rule already allows it: `CLAUDE.md` should be brought in line with the desktop's.

| # | Step | Done when |
| --- | --- | --- |
| 6.1 | **ADR 3: the store on the phone.** Sign-in on Android for both services (Login Flow v2 and OAuth with PKCE need a browser and a way back into the app), where the tokens and the key are kept, the packages needed (or none: `dart:io` `HttpClient` for WebDAV and Dropbox's HTTP API, `crypto` has no AES-GCM), and the formats of ADR 8 ported with the desktop's test vectors. | The owner has accepted it. `CLAUDE.md`'s offline rule matches the desktop's. |
| 6.2 onward | Written from the accepted ADR, with the desktop's step S8. | |

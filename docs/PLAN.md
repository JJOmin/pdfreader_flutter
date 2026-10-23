# Plan

The Flutter port of `../pdfreader`, Android first. Decisions are in
[adr/0001-flutter-port.md](adr/0001-flutter-port.md).

Each step ends with a check that shows it works. "Device" means the owner's phone over USB, with
`flutter run` or `integration_test`, plus a note of what was seen. Without a phone a step is
reported as **not verified on device**. Work stops after each milestone for the owner's review.

Every step that adds logic writes the test first. A port of a TypeScript test keeps its name, its
inputs and its expected outputs.

## Order from here (the owner, 2026-10-22)

The owner moved to a MacBook Air M1, with Flutter through FVM and the Android phone on the Mac.

1. **The desktop app on the Mac**, steps MAC0 to MAC5 in the desktop's `docs/SPEC.md`. Nothing new
   on the phone meanwhile, except that MAC4 runs the sync tests against the Mac.
   **2026-10-22:** MAC4 done for Wi-Fi: `desktop_sync_test`, `reader_test` and `notes_sync_test`
   pass against the Mac (with its VPN off; the desktop now warns about VPNs).
2. **Asked 2026-10-22 after MAC5. The owner chose "sync 2", M7 below**: no Dropbox for now,
   Nextcloud fast and automatic, a phone library that shows what is on the phone and what is only
   in the cloud, pairing by QR code, Wi-Fi sync that works like the cloud, and sending a document
   from the desktop. Opening a PDF from Finder with the installed Mac app works (owner, MAC5).
   The rest waits:
   - Dropbox (6.6), removed for now in 7.1.
   - The open device checks: 1.7 pinch zoom, 1.11 at 300 %, 1.12 screen off and the
     notification, 5.4 Remove, 2.6 seen in the desktop app, 5.1 a German paper.
   - M4: export and the annotated PDF.
   - **iOS**, last: the Swift side of the platform channels. There is no iPhone yet, so the
     simulator first.

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
| 5.7 | **Done 2026-10-21.** `lib/shared/notes_merge.dart` with the desktop's test cases, and a golden file with the new fields written by the desktop, equal byte for byte. Device, phone and the desktop app on this computer, with `integration_test/notes_sync_test.dart`: two marks and a comment made on the phone reached the desktop; the desktop's edit of that comment and its own new mark reached the phone; a mark deleted on the phone disappeared on the desktop and is a removal there. Sync sends the phone's notes for each prepared document and keeps the merge. **Notes both ways.** `notes.json` joins the library (desktop step S9). The phone sends its notes with `PUT` and fetches the desktop's. Merged per mark, as the owner chose on 2026-10-21 (desktop ADR 7 section 1): marks are kept by id from both sides, an edited mark takes the newer edit, a deleted mark stays deleted (a tombstone), and the general notes take the newer text. `lib/shared/notes_merge.dart` with tests, the same cases as the desktop's. | Unit tests for the merge: new on both sides, edited on both, deleted on one and edited on the other. Device: a mark made on the phone shows on the desktop after a sync, and one made on the desktop shows on the phone. Neither is lost when both changed before the sync. **Stop for review.** |

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
| 6.1 | **ADR 3: the store on the phone**, written 2026-10-21 and **proposed**: [adr/0003-the-store-on-the-phone.md](adr/0003-the-store-on-the-phone.md). It waits for the owner's four choices in its section 7 (the AES-GCM package, Dropbox's redirect, where secrets are kept, the first service). | The owner has accepted it, and `CLAUDE.md`'s offline rule matches the desktop's. |
| 6.2 to 6.5 | **Done 2026-10-21**, against stand-ins; 6.6 is not done. 6.2: `lib/shared/sync_store.dart`, 20 tests with the desktop's golden files (a file sealed by the desktop opens on the phone, and the phone writes the very same bytes for the same IV), and `SecretBox` and the browser channel, run on the phone. 6.3 and 6.4: `lib/store/` with 30 tests against stand-in servers written from the documentation. 6.5: the Cloud screen, `lib/store/store_sync.dart` with 21 tests against a store the desktop's own engine wrote, and `integration_test/cloud_test.dart`, which on the phone signs in to a stand-in Nextcloud on the PC over Wi-Fi, enters the key, downloads the sample (0.7 s), syncs, and sends a mark the desktop's code then opens, three runs in a row. The desktop's S8b is done. The formats and `SecretBox`, the WebDAV store and Nextcloud sign-in, the Dropbox store and sign-in, the Cloud screen, and a run on the device with real accounts. Listed in the ADR's section 8, with the desktop's S8b (notes through the store). | Per step, in the ADR. |

## M7: sync 2 (desktop ADR 10)

Designed in `../pdfReaderWindows/docs/adr/0010-sync-2.md`, **accepted** 2026-10-22; its owner's
choices decide 7.6 and 7.8. Each step is built with its desktop step (S10 to S15 in that
repository's `docs/SPEC.md`) and tested against it on the device. This repository's ADR 4 records
the phone's packages once the owner chose them.

| # | Step | Done when |
| --- | --- | --- |
| 7.1 | **Done 2026-10-22.** 276 unit tests with `tool/check.sh`, the debug APK builds; the redirect channel (`platform_oauth.dart`, the Kotlin `pdfreader/oauth` channel and the manifest's scheme) went too, since only Dropbox used it. A `cloud.json` that names Dropbox reads as signed out. Tests that read the desktop's fixtures find `../pdfreader` or `../pdfReaderWindows` (`test/desktop_repo.dart`). **Remove Dropbox** (with S10): `lib/store/dropbox_store.dart`, its part of `cloud_accounts.dart` and `cloud_page.dart`, the redirect in the Android manifest, `test/store/dropbox_test.dart` and its fake server. ADR 3 gets a note. | `tool/check.ps1` passes; nothing in `lib/`, `test/` or `android/` mentions Dropbox. |
| 7.2 | **Done 2026-10-22, not verified on device.** 296 unit tests with `tool/check.sh`. `shared/sync_store.dart` reads and writes `devices/<device>.json` and reproduces the desktop's golden journal (`test/golden/journal.json`, written by the desktop's S11) byte for byte; `shared/sync_memo.dart` and `store/memo_file.dart` keep the journals read (with their ETags), the phone's own journal and the hashes of what was last exchanged; `StoreSync.sync` lists `devices/` once, opens only journals whose ETag moved and fetches only the documents and parts they name, plus whatever changed on the phone. `full: true` walks everything and writes a lost journal again; a document another device's journal names that the phone does not hold comes back as `newInCloud` for 7.4. The Cloud screen's Sync button still walks everything (`full: true`) until 7.3 adds the automatic sync that uses the journals; a new account or key clears the memo. The `cloud_test` integration test needs a stand-in Nextcloud served from the desktop and was not run. The change journal (with S11): `lib/shared/sync_store.dart` reads and writes `devices/<device>.json` with the desktop's golden files; `store_sync.dart` fetches only what changed; a full walk on request. | Unit tests with the desktop's cases and a golden journal written by the desktop. |
| 7.3 | **Done 2026-10-22, not verified on device** (the debug APK builds; nothing was installed). 317 unit tests with `tool/check.sh`. `shared/auto_sync.dart` (`AutoSync`) syncs when the app starts or comes to the front, every 30 s while it is open and 5 s after a mark or comment; a place goes with the next poll, so turning pages sends nothing by itself; never two at once. `sync_controller.dart` owns the engine, the memo and the one-at-a-time queue (the Cloud screen's downloads go through it too), and `shared/sync_state.dart` is the desktop's four states. The home screen has the icon (it opens the Cloud screen), pull to refresh walks the whole store, and the app syncs on `resumed` and flushes a waiting change on `paused`. Notes the sync merged in do not count as the phone's own change, so a sync does not trigger the next. Tests use a clock the test moves (`test/fake_timers.dart`) and a stand-in Nextcloud. Automatic sync on the phone (with S12): on start and resume, every 30 s while open, 5 s after its own change; pull to refresh walks everything; an app-bar icon with the desktop's four states. | Unit tests for the timing (fake clock). Device: a mark made on the Mac shows on the phone within 45 s with no tap, and at once after a pull to refresh. |
| 7.4 | **Done 2026-10-22, not verified on device** (the debug APK builds; nothing was installed). 340 unit and widget tests. The home screen is one list (`library_list.dart`, states and filters in `shared/library_view.dart`): On this phone, Update available, In the cloud, Downloading n %, filter chips All / On this phone / Cloud only, "1.2 GB on this phone", and a menu per document (Open, Download or Download update, Remove from this phone). A tap opens a document that is here and downloads one that is not, whatever the network. The cloud's documents come from `store/cloud_catalog.dart`, which a full walk replaces and the journals add to (`SyncSummary.cloud`). Automatic syncs leave an update for the user on a metered network (`isMetered` on the existing `pdfreader/discovery` channel, `ACCESS_NETWORK_STATE`). Not in this step: documents offered by a paired computer over Wi-Fi (7.7, 7.8); the Desktops screen still lists those. One library (ADR 10 section 4): every document with its state (on this phone, update available, in the cloud, downloading, offered), filter chips, space used, Download and Remove from this phone. Automatic downloads wait for Wi-Fi (metered network through the existing channel). | Widget tests for each state and the filters. Device: download a cloud-only document, remove it again, and it stays listed as in the cloud. |
| 7.5 | **Built 2026-10-22, not verified on device; stop for review of the design.** 339 unit and widget tests with `tool/check.sh`, the debug APK builds. `sync_page.dart` is the one Sync screen, reached from the sync icon (or "Set up sync" when the list is empty): the Nextcloud account, key and "Refresh everything" (`cloud_section.dart`) above the computers on Wi-Fi (`desktops_section.dart`). `cloud_page.dart` and `desktops_page.dart` are gone, and so are the Desktops icon and the "Connect to a desktop" button. The cloud's document list moved to the home screen (7.4). "Scan to pair" comes with 7.6. The three integration tests were changed to the new screens and **were not run**: `cloud_test` drives `CloudSection` on its own and downloads through the controller, and `desktop_sync_test`, `notes_sync_test` and `place_test` reach the Sync screen through the sync icon (`integration_test/finders.dart`). They need the stand-in servers and the desktop, so the "done when" is open until they pass on the phone. One Sync screen: the Nextcloud account and key, the paired computers, "Scan to pair". Desktops and Cloud screens go. | The integration tests (`cloud_test`, `desktop_sync_test`, `notes_sync_test`) pass on the new screens. **Stop for review** of the phone's design. |
| 7.6 | **Done 2026-10-22: the owner paired the phone with the Mac by scanning the QR code.** 344 unit and widget tests with `tool/check.sh`, the debug APK builds and its merged manifest has the camera permission. `shared/pairing.dart` reads the desktop's `pdfreader://pair?...` string (tested against the very string the desktop's tests make), `pairFromQr` tries the addresses in the picture and sends the secret, `scan_page.dart` is the camera page (`mobile_scanner`, recorded in ADR 4; the permission is asked when it opens, a refusal says to type the code), and the Sync screen has "Scan to pair". The pairing itself (TLS to the desktop) has no unit test; it needs the desktop. **Device test left:** scan the Mac's Phone dialog in the light you read in (ADR 10 "not verified": does the scanner read a QR from a laptop screen in poor light), and the old typed code. Pair by QR (with S13): the scanner (owner's choice 3), the camera permission asked on the first tap, pairing with the secret. | Device: scanning the Mac's dialog pairs in one step; the old typed code still works. |
| 7.7 | **Done 2026-10-22: the owner reports marks syncing well between the Mac and the phone on the same Wi-Fi.** 352 unit and widget tests; the desktop's S14 e2e passes. `wifi_sync.dart`: while the app is open it listens for the paired computers, syncs with one as soon as it is heard, then asks `GET /v1/changes` every 5 s and syncs when something changed or the phone changed something (a place too). A computer that goes away is let go and synced again when heard; one that is heard but unreachable (a VPN) is tried again after 30 s; one of protocol 1 is synced when heard, at most every 30 s. An automatic Wi-Fi sync keeps up to date only what is on the phone (`onlyHeld`); new documents still come through the Sync screen's button. Wi-Fi syncs share the cloud's one-at-a-time queue, notes merged from Wi-Fi do not start another sync, and Android's multicast lock is now counted, as the Sync screen and the Wi-Fi sync listen together. Wi-Fi like the cloud (with S14): heard computers are synced at once, then polled every 5 s while the app is open. | Device: a mark made on the Mac shows on the phone within 10 s on the home Wi-Fi. |
| 7.8 | **Built 2026-10-22, installed on the phone, not yet tried against the Mac. Stop for review.** 360 unit and widget tests. `shared/inbox.dart` reads the desktop's offers; they come over Wi-Fi (`GET /v1/inbox` at each 5-second poll) and, away from home, in the desktop's change journal (`offers`; desktop S15 explains why not `inbox/<device>.json`). The library shows "Offered by Leos-MacBook · 12 MB"; a new offer asks "Leos-MacBook sends paper.pdf (12 MB)" with Accept, Decline and "Always accept from this computer" (`store/offer_file.dart` remembers the answers and the computers). Accept downloads from the computer itself when it is on the same Wi-Fi, else from the cloud; an always-accepted offer downloads by itself, from the cloud only on a network that is not metered. Decline is told to the computer over Wi-Fi; away from home the phone only remembers it, and the offer stays in the desktop's journal until the next time the phone is on its Wi-Fi. Accept a sent document (with S15): the offer in the library and as a prompt, "Always accept from this computer" (owner's choice 1), Wi-Fi only for automatic downloads. | Device: "Send to phone" on the Mac shows the offer, Accept downloads it, Decline removes it. **Stop for review.** |
| 7.9 | **Done 2026-10-22 in code, installed on the phone, not yet tried against the Mac.** 366 unit and widget tests. **Every PDF synced, its audio page by page** (desktop ADR 11, with S16 and S17): the manifest of version 2 (`voiced`, `voices`; version 1 read as every page voiced), `pagesToFetch`, and downloads from the cloud and over Wi-Fi that fetch only the pages the phone lacks (all of them when the voices changed). The library says "no audio yet" or "audio 3 of 10 pages"; the reader reads the voiced pages and says how far the audio is. | Unit tests with the desktop's cases. Device: open a PDF on the Mac; it is on the phone's list within a minute, without audio, and pages get audio while the Mac renders. |

## M8: improvement round 1 (desktop SPEC, "improvement round 1")

Asked by the owner on 2026-10-22: finish sync 2, reading quality and M4, in one commit per
repository, built step by step (R1 to R9 in the desktop's SPEC). The phone's parts. **Ticked by the
owner on 2026-10-23:** all of 8.1 (the three sync checks, a sentence over a page break heard as one,
the Markdown export, a saved PDF with marks opened in the desktop app), so 8.4 to 8.6 hold on the
device too; also 6.6 with a real Nextcloud, and 1.7 and 1.11 (pinch zoom, sharp at 300 %). Sync
while the app is closed (the desktop's R8) was dropped by the owner on 2026-10-23.

| # | Step | Done when |
| --- | --- | --- |
| 8.1 | **Device checklist for sync 2** (owner), and since 2026-10-23 also: open a paper with a sentence over a page break and hear it as one; Export notes as Markdown; Save PDF with marks and open the copy in the desktop app: away from home, a mark made on the Mac is on the phone within about 45 s; Send to phone → Accept downloads, Decline removes; a PDF opened on the Mac shows "no audio yet" and gets its audio page by page. | The owner ticks them here. |
| 8.2 | **Done 2026-10-23.** The switch is in the reader's text settings. **Stop at the reference list** (with R2): the option from `settings.json`, the same heading match as the desktop. | Unit tests with the desktop's cases. |
| 8.3 | **Done 2026-10-23.** The golden page words of both PDFs match. **No figure, table or formula text** (with R3, R4): `layout.dart` makes the desktop's choices. | Unit tests ported; the golden page words of both sample PDFs match again. |
| 8.4 | **Done 2026-10-23 in code** (desktop ADR 12): `joinedPage`, `Word.page`, `PlannedSentence.next`; the sentence is tinted on both pages. Not verified on the device. **A sentence over a page break read as one** (with R5, ADR 12). | Unit tests; device: the highlight moves onto the next page with the voice. |
| 8.5 | **Done 2026-10-23 in code, installed, not verified on the device.** **Markdown export** (4.2) through the system "save as" picker. | Unit test; device check. |
| 8.6 | **Done 2026-10-23.** `lib/annotated_pdf.dart`; `pdfium_dart` and `ffi`, which pdfrx already brings, are now declared (ADR 4). PDF.js reads what it writes. **Save PDF with the marks** (4.3, 4.4) through PDFium's annotation API. | The owner sees the marks in the desktop app. |

## M9: the app's structure (the owner, 2026-10-23)

Asked after M8's review: tabs, a Now Playing bar that keeps reading while the user looks
elsewhere, favourites and folders, and "Read from here" as on the desktop. No new package.

| # | Step | Done when |
| --- | --- | --- |
| 9.1 | **Done 2026-10-23.** Device: in the pages view, ▶ in the menu over “Ausgleichszeitraums” started at its sentence. Not tried in the reading view. **Read from here** in the mark menu: a play button reads from the sentence the selection starts in, as the desktop's `readFrom` (first sentence on the page with a range ending after the offset, else the next page's first). Shown only for a prepared document. | Unit tests for the sentence lookup. Device: select a word in the middle of page 2, tap ▶, and reading starts at its sentence, in both views. |
| 9.2 | **Done 2026-10-23.** Device: the tabs, Continue reading (with its page) and New on this phone on the owner's library; Settings with Nextcloud and the paired Mac. **Tabs**: a bottom navigation bar with Home, Favourites and Settings. Home: "Continue reading" (the documents read last, by their saved place) and "New on this phone" (downloaded, not opened yet, newest first), then the whole library as before. Settings: the sync of 7.5 (Nextcloud, computers) and the reading options (speed, stop at the reference list). The sync icon on Home opens the Settings tab. | Unit tests for both short lists. Widget test: the three tabs switch. |
| 9.3 | **Done 2026-10-23.** Widget test as asked; device: a like from the bar shows under Liked, and the "+" sits above both bars. No folder was made on the owner's phone. **Favourites and folders**: a heart likes a document; a folder has a name, a colour and notes, and holds any number of documents, so a folder works as a tag ("Arbeitsvertrag.pdf" in "Verträge"). The Favourites tab: a search at the top over every document's title and folder names, chips to filter by Liked or a folder, the folders, and a "+" above the bars that makes a folder. A document's menu gets Like and "Folders…". Kept on this phone only, in `favourites.json`. `// shortcut: not synced; when the desktop gets folders, they join the library like notes`. | Unit tests for the model, its file and the search. Widget test: make a folder, put a document in it, find it by the folder's name. |
| 9.4 | **Done 2026-10-23, waiting for review.** Device: Back while reading kept the voice going, with Pause and the shortened title in the bar; Next and the heart worked; a tap on the bar showed the reader on page 2, where the voice was; the speed sheet opens from the icon. The integration tests were changed to the new navigation (`closeDocument`, `sampleTile` in `finders.dart`) but **not run**: `sample.pdf` is no longer on the phone. **Now Playing**: an open document becomes the session. Back hides the reader and the voice goes on; above the navigation bar a one-line bar shows play or pause, the title (shortened with …), the heart and "next sentence". A tap on it opens the reader again, without the navigation bar. The reader's own bar: previous, play or pause and next in the middle, the speed behind an icon at the right; Stop is gone. Opening another document ends the session; swiping the bar away ends it too. | Widget test for the bar. Device: start reading, go Back, the voice goes on and the bar's buttons work; tap the bar, and the reader is where the voice is. **Stop for review.** |
| 9.5 | **Done 2026-10-23** (asked after 9.4). The reader's buttons sit 20 px higher. "n sentences have no audio and are skipped" is no longer a status line but a toast when the document opens, and "Skipped a sentence without audio" is a toast when the voice passes over one (`PagePlan.skippedBefore`, `skippedBetween`, with tests); only while the reader shows, so the Now Playing bar stays clear. Device, on "Arbeitsvertrag … (old).pdf": the toast at opening, and at each page break whose last sentence has no audio. | Unit tests; device: both toasts seen. |
| 9.6 | **Done 2026-10-23.** A small tab at the reader's bottom right hides the play bar (↓) and brings it back (↑); kept across documents while the app runs. Device: hidden, the page reaches the bottom; shown again, the bar is as before. | Device: both ways seen. |
| 9.7 | **Done 2026-10-23.** The reader's play bar is rounded, 10 px above and below its buttons: previous, play and next at the left, the title running through when it is too long (`views/marquee.dart`), the speed at the right. Both bars take a shade of what is behind them (the grey around the pages, or the reading view's light, sepia or dark), and the page behind them is that colour too. A tap on the page that is not on a mark hides the top bar and brings it back, as in a photo gallery (not while searching). Search and Text settings moved into the ⋮ menu. Device: sepia and pages colours, the running title, the tap in both views, the menu. | Device: seen. |
| 9.8 | **Done 2026-10-23.** The play bar and its notch lie over the page, which runs on behind them. The pages view can scroll 120 px past the last page (pdfrx's `boundaryMargin`), as the reading view already could, so the end is not stuck under the bar. Device: the page shows around the rounded bar in the pages view. | Device: seen. |
| 9.9 | **Done 2026-10-23.** The reader's play bar sits on the bottom edge, its top corners rounded; both reader bars stand out more from the page (a 14 % step towards the text in the reading view, a darker grey in the pages view). The Now Playing bar on the tabs is rounded too, 8 px above the navigation bar. Device: all three seen. | Device: seen. |
| 9.10 | **Done 2026-10-23.** Both bars are 6 px from the screen's sides (was 12). The reader's play bar is 12 px lower (4 px above and below its buttons, play button 24 instead of 28); the Now Playing bar on the tabs is 12 px higher (6 px above and below). Device: both seen. | Device: seen. |
| 9.11 | **Done 2026-10-23.** A dark theme that follows the system's light or dark setting (`darkTheme`, `themeMode: system`); the area around the pages is dark grey in dark mode (`pagesBackdrop`) and the reader's bars follow; the navigation bar is 56 px high (was 80). The reading view keeps its own light, sepia and dark choice. Device: Home, the reading view and the pages view seen with the phone set to night mode, then back to automatic. | Device: seen. |
| 9.12 | **Done 2026-10-23.** The Settings tab is a list; each entry opens a page of its own: **Appearance** (same as the system, light or dark; `shared/app_settings.dart`, `app_settings_store.dart`, kept in `app-settings.json`, with a test), **Reading aloud** (the speed the next document starts with, stop at the reference list), **Nextcloud**, and **Computers** (scan to pair, type an address). Device: all four pages seen; Light overrode the phone's dark mode at once and was still set after a restart; set back to the system's. | Device: seen. |
| 9.13 | **Done 2026-10-23.** Home loses its two buttons at the top; a round button over the list's corner (like the folder button) opens the system picker. The app is offered by Android for a PDF: "Open with" (`VIEW`, content and file addresses) and "Share" (`SEND`) in `AndroidManifest.xml`; `MainActivity.kt` keeps the address until Flutter takes it (`takeIncoming`), or tells a running app (`incoming`). The app's label is now "PDF Reader". A PDF the desktop prepared is found by its bytes, as with the picker. Device: Android lists the app for both intents; a PDF sent while the app was closed and one sent while it ran both opened in the reader. **Not tried: another app's own "Open with" menu** (adb sent the intents). | Device: seen with adb; the owner tries a real app. |
| 9.14 | **Done 2026-10-23.** A PDF another app hands over opens in the reading view at once (`startInReading`). A document with no audio (not prepared by the desktop, or no page voiced yet) shows no player: no bar in the reader, no notch, no "Read from here", and no Now Playing bar on the tabs; Back closes it instead of leaving it running (`ReadingSession.hasAudio`, with a test). Device: an unprepared PDF sent from outside opened in the reading view with no player, and Back went to Home with no bar; a prepared one opened in the reading view with the player and left the bar behind. | Device: seen. |

## M10: the phone's own voice (the owner, 2026-10-23)

Asked after M9: use the phone's native text-to-speech when the desktop's audio is missing, always
prefer the prepared audio, and show which of the two is playing. Decided in
[ADR 5](adr/0005-the-phones-own-voice.md). No new package.

| # | Step | Done when |
| --- | --- | --- |
| 10.1 | **Done 2026-10-23.** 417 unit and widget tests with `tool/check.sh`. `planPage(…, phoneLangs:)` gives a sentence the desktop lacks to the phone (`PlannedSentence.source`, `spoken`); `PreparedAudio.timings` lets the player report timings it measured; `lib/phone_voice.dart` and `PhoneVoice.kt` (the `pdfreader/tts` channel, `synthesizeToFile`, offline voices only, one request at a time); `LibraryAudio` plays the file through `just_audio` and estimates the words; `ReadingSession.hasAudio` is true with a phone voice. Device: `integration_test/phone_voice_test.dart` on the S20 FE (Samsung TTS): German and English found offline and rendered in 287 and 340 ms; an unprepared one-page PDF is read by the phone, both sentences, the word mark advancing, Pause working. **Phone voice for what the desktop did not prepare.** | Unit tests for the plan (no index, differing words, language not spoken, nothing to say), for the player's timings and for the channel. Device: an unprepared PDF is read aloud. |
| 10.2 | **Done 2026-10-23.** A computer or phone icon beside the speed button in the play bar and in the Now Playing bar (`SpeechSource`, `AudioSourceBadge`), a status line for a document with no computer audio yet, and a toast for a prepared document's phone sentences. Widget tests for the badge; device: the phone icon seen by the integration test. **Show where the audio comes from.** | Device: a prepared page shows the computer, an unprepared one the phone. **Open: the computer icon on a prepared document (none was on the phone) and a mixed document heard by the owner.** |

## M11: the full-screen player (the owner, 2026-10-23)

Asked after M10: the reader's player becomes the menu's small bar, a tap on either opens a
full-screen player like a music app's, built to be used while driving, with a speed-reader preview,
a quick comment and spoken comments. Decided in
[ADR 6](adr/0006-the-full-screen-player-and-spoken-comments.md). No new package; new permission
`RECORD_AUDIO`.

| # | Step | Done when |
| --- | --- | --- |
| 11.1 | **Done 2026-10-23.** The reader's bar is `NowPlayingBar`, the menu's, with a 13 sp title and no source icon (`barKey`, `playKey`, `onClose` null in the reader); `ReadingSession` carries the sentence, word, neighbours and speed, and callbacks for speed and comment. Device: both bars seen alike. **One small bar.** | Widget tests; device: seen. |
| 11.2 | **Done 2026-10-23.** `lib/player_screen.dart` (`PlayerScreen`, `PlayerLayer`), opened from both bars in `main.dart`, Back minimises it first. `shared/player_preview.dart` (`wordSpans`, `steppedSpeed`, `sentenceText`, 7 tests). Device: opened from the reader, the controls in the lower two fifths, Back minimised and a second Back returned to the menu with its bar. **The full-screen player.** | Widget tests (position, buttons, speed, slide); device: seen. |
| 11.3 | **Done 2026-10-23.** `lib/views/speed_reader.dart`: highlight on the spoken word, dimmed past words, scrolling, faded neighbours (4 widget tests). Device: on a prepared document the word moved with the voice. **The preview window.** | Widget tests; device: seen. |
| 11.4 | **Done 2026-10-23.** `lib/views/quick_comment.dart`, `ReaderPage._commentOnSentence`: pause, comment, mark the sentence, resume. Device (`integration_test/phone_voice_test.dart`): the mark has the comment and the sentence's exact range, and the voice read on; the sheet seen on the phone (a 10 px overflow at phone width was found there, fixed, and has a test). **Comment without touching the text.** | Widget tests; device test. |
| 11.5 | **Done 2026-10-23, in two goes.** First on Android's own recogniser, which could not be bound on the owner's phone (ADR 6). Then on the phone with sherpa-onnx: `lib/shared/endpoint.dart` (10 tests), `lib/speech/transcriber.dart`, `lib/dictation.dart`, `Dictation.kt` (microphone only), the microphone in the sheet and in the mark menu, a draft in the field, a five-second wait for a first word. 459 unit and widget tests. Device (`integration_test/dictation_test.dart`): the model understands the phone's German and English voice, the microphone opens, and the phone's voice played into its own microphone is written out with partial results. **Not tried: a person speaking.** **Spoken comments.** | Device: speak a comment and see it as a draft. |
| 11.6 | **Done 2026-10-23.** The full-screen player is leaner: one rounded panel on the bottom edge holds the source line and speed, previous, play (56 and 72 dp) and next, and Comment and Speak (44 dp) side by side. It is about a quarter of the screen (a widget test keeps it under 25 %), and the text takes the rest instead of the upper three fifths. The reader no longer shows the "Audio from the computer…" box: only an error from the audio is shown above the bar, and where the audio comes from is the player's line ("Page 9 · phone voice"). The bar hides with the top bar (M14). Device: both seen, in dark mode. **Leaner player, no status box.** | Widget test; device: seen. |
| 11.7 | **Done 2026-10-23.** The recogniser model (`model.int8.onnx`, `tokens.txt`, 127 MB) was pushed to the S20 FE with `adb push` into the app's `models` folder, as ADR 1 option B says; the DE/EN switch in the comment sheet went, as the model finds the language itself. **Speech on the phone.** | Device: seen. |

## M12: comment icons (the owner, 2026-10-23, both repositories)

Asked after M11: a small icon above a marked section that has a comment, a note for a typed comment
and a microphone for one made by speech, in the phone app and in the desktop app. The notes file gets
one new optional field, so this changed `../pdfReaderWindows` too, at the owner's request.

| # | Step | Done when |
| --- | --- | --- |
| 12.1 | **Done 2026-10-23.** A mark may carry `"via": "speech"`, written between `created` and `updated` (`lib/shared/notes.dart`, the desktop's `src/shared/notes.ts` and `types.ts`). A file without it reads and writes as before and an unknown value is ignored; it travels with the mark through `mergeNotes` and counts as a change in `stampChanges`. `markBadge` is the one rule in both: nothing without a comment (blank is none), a note for a typed one, a microphone for a spoken one. `tests/golden/notes-via.json`, written by the desktop's `JSON.stringify`, is read byte for byte by both (`test/golden/notes-via.json`). 474 phone tests, 326 desktop unit tests. **The file and the rule.** | Unit tests on both sides, with the shared golden file. |
| 12.2 | **Done 2026-10-23.** The comment sheet reports whether any text was spoken (`QuickComment.dictated`, kept when the draft is corrected by hand, not set when nothing was heard), and `ReaderPage._addMarks` writes `via`. A comment typed on a mark's card keeps the mark's `via`. **Setting it.** | Widget tests; device test. |
| 12.3 | **Done 2026-10-23.** Pages view: `shared/mark_badge.dart` (`badgeBox`, 3 tests) places the icon over the first line of the mark, `views/mark_badge.dart` paints it, last, over every mark; a tap on the icon opens the comment. Reading view: `_BadgePainter` over each paragraph that holds a mark's first line. Device (`integration_test/phone_voice_test.dart`, screenshots): a spoken comment (a recogniser that always hears the same words) got the microphone, a typed one the note, in the pages and in the reading view. **The icons on the phone.** | Device: seen in both views. |
| 12.4 | **Done 2026-10-23.** `mark-badges.ts` puts a 14 px button above the first line of the mark in the scrolling container, in the mark's colour; it is repainted with the marks and as a comment gains its first words or loses its last; a click shows the comment in the sidebar. Desktop `tests/e2e/badges.spec.ts` (6 tests: kinds, position, scrolling, click, typing, reading view) and a screenshot. **The icons on the desktop.** | e2e passes. |

Not done: a person dictating a comment and seeing the microphone; the desktop cannot dictate, it only
shows what the phone made. Markdown export and the PDF copy do not mention how a comment was made.

## M13: the comment menu and the choice of voice (the owner, 2026-10-23)

| # | Step | Done when |
| --- | --- | --- |
| 13.1 | **Done 2026-10-23.** The selection menu's microphone is a Comment button (`comment-selection`, shown for every selection, with or without a recogniser). It opens the comment sheet, where the comment is typed, or spoken with the microphone in the sheet if the phone can listen. Device (`integration_test/phone_voice_test.dart`): a long press on a word showed the menu with Comment and no microphone, the sheet opened, a typed comment was saved on the selection, in the reading view and in the pages. Through adb, taps on this menu's buttons did nothing, "Read from here" included, so the check is the integration test. **Comment from a selection.** | Widget test for the menu; device test. |
| 13.2 | **Done 2026-10-23.** The full-screen player has a switch between the computer's prepared audio and the phone's own voice (`VoiceChoice`, two icon buttons), shown only where the computer voiced a page and the phone can speak (`ReadingSession.canSwitchVoice`). The caption under the title says which audio is playing. Switching drops the plans and the loaded audio (`Reader.forget`), finds the sentence of the other voice that starts where the old one did (`readFromIndex`) and goes on there, reading if it was reading. The choice is kept across documents while the app runs. With the phone's voice chosen the saved place keeps no sentence number, because the phone's sentences are not the desktop's. Device, on a prepared document: computer audio, tap the phone icon, the caption said "phone voice" and the next sentence was the phone's, and back. **Choose the voice.** | Widget tests (switch, narrow phone, session rule), reader test (`forget`); device: seen. |

## M14: bars, a fast scroller and closed cards (the owner, 2026-10-23, both repositories)

| # | Step | Done when |
| --- | --- | --- |
| 14.1 | **Done 2026-10-23.** The reader's play bar goes with the top bar: a tap on the page hides both and brings both back (`ReaderPage._toggleTop`; search keeps them). The tab above the bar and `_barHidden` are gone. Device: a tap on the page hid both. **One way to hide.** | Device: seen. |
| 14.2 | **Done 2026-10-23.** A grip on the right edge with the page number, dragged to scroll a long document: pdfrx's `PdfViewerScrollThumb` in the pages (`viewerOverlayBuilder`), `lib/views/fast_scroll.dart` (`FastScrollThumb`, 3 widget tests) in the reading view, in place of its thin `Scrollbar`. Device (pages view): one drag moved the document several pages. Not seen on the device: the reading view's grip. **Fast scroller.** | Widget tests; device: seen in the pages. |
| 14.3 | **Done 2026-10-23.** A mark's card (`MarkCard`, in the notes sheet and under a tap on a mark) only shows until its pencil opens it: the comment is read-only, and the kind, the colour and Delete show only while open. The phone could not change a mark's kind or colour before; it can now, through `NotesActions.onStyle`, and the change syncs like any other. The desktop's cards work the same (its SPEC). `test/notes_sheet_test.dart` (4 tests). `integration_test/marks_test.dart` taps the pencil first; it could not be run (it needs the prepared `sample.pdf` in the library). Not seen on the device. **Closed cards.** | Widget tests; device: not seen. |
| 14.4 | **Done 2026-10-23.** The reader's play bar and its error line take the colours of the top bar (`NowPlayingBar.colors`, `ReaderPage._barColors`): in the reading view the chosen theme (light, sepia, dark), in the pages the same grey as the top bar. The menu's bar and the full-screen player keep the app's colours. `test/now_playing_colors_test.dart` (2 tests). Device: sepia seen in the reading view, grey in the pages. **Bar colours.** | Widget tests; device: seen. |

## M15: one look for the whole app (the owner, 2026-10-23)

Asked after M14: the light and dark choice and the reading view's colours become one setting for the
whole app, with a font and a text size for the app, and the reading view keeps only its type.

| # | Step | Done when |
| --- | --- | --- |
| 15.1 | **Done 2026-10-23.** `shared/app_settings.dart` (`Appearance`: system, light, sepia, dark or custom; font; text size 80 to 160 %; the custom theme's background, text and accent), `app-settings.json` reads the old file (only `theme`) and writes the new fields. A custom text colour must reach a contrast of 3 on its background, and a new background brings the best offered text if the old one would not (`withBackground`), so no choice leaves the app unreadable. `shared/app_settings_test.dart` (10 tests). **The model.** | Unit tests. |
| 15.2 | **Done 2026-10-23.** `lib/app_theme.dart` builds the themes (light and dark are the stock look; sepia and custom step the surfaces from the background towards the text, as the reader's bars did) and `scaleText` multiplies the system's text size by the app's. `MaterialApp` uses both, so every screen follows. The reader's bars, page and play bar take the scheme's colours; `readingThemeColors` is gone. `app_theme_test.dart` (7 tests). **The whole app follows.** | Unit and widget tests; device: seen in sepia on Home, Settings and the reader. |
| 15.3 | **Done 2026-10-23.** Settings, Appearance: colours (system, light, sepia, dark, custom with swatch rows), font, text size, and Speed reader as a page under it with the reading view's font, size, line and letter spacing and a preview. The reading view's own light/sepia/dark buttons are gone; the sheet in the reader's menu keeps the type controls. `Places` tells an open reader when the reading settings change. The reading view keeps its own text size: only the system's setting reaches it, not the app's. `appearance_settings_test.dart` (5 tests). Device: Appearance, Speed reader, Home at 160 % without overflow, reading view. **Appearance and Speed reader.** | Widget tests; device: seen. |

Note: the reading settings still hold a `theme` field, the desktop's file format, but nothing reads it.
The desktop app's colours are unchanged: it has its own settings.

## M16: security, CI and accessibility (the owner, 2026-10-23, both repositories)

| # | Step | Done when |
| --- | --- | --- |
| 16.1 | **Done 2026-10-23.** A review of both apps (`SECURITY.md` here and in the desktop repository). Phone: backup off, `file:` access to the app's own storage refused, a size cap on a document, release signing from a key and not the debug key. Device: the new build installed over the old one, the `file:` intent did nothing, the backup flag is gone from the package. **Security review.** | Device: seen. |
| 16.2 | **Done 2026-10-23, not yet run on GitHub.** `.github/workflows/`: `ci.yml` (analyze, format, tests, a release build on every pull request and push to main), `security.yml` (dependency review, secret scan), `release.yml` (a `v*` tag builds the signed app and attaches it to a release; it refuses without the owner's key). Dependabot for pub, Gradle and the actions. Features go on `feature/...` branches (CLAUDE.md). The files are valid YAML; they have not run, because nothing is pushed. **CI/CD.** | The first pull request shows green checks. |
| 16.3 | **Done 2026-10-23.** `test/accessibility_test.dart` runs Flutter's guidelines (48 dp targets, a label on every control, text contrast of 4.5) on Home, Favourites, Settings, Appearance, Speed reader, a mark's card and the play bar in the light, dark, sepia and a custom theme. It found and fixed: swatches and the pencil under 48 dp, a search field 24 dp high, sepia text at 4.0 contrast. The fast-scroll grip has a 48 dp area and a name, and a screen reader steps it. The custom colours have names and are refused below contrast 4.5. The status line, the search count and the place offer are announced. 529 tests. Not on the device with TalkBack. **Accessibility.** | Widget tests; device: not checked with TalkBack. |

Correction (M17): a screen reader can read the PDF pages. pdfrx builds a text layer for them; this note
first said it could not, before anyone had looked.

## M17: the name Easy Reader, and screen readers in the reader (the owner, 2026-10-23)

| # | Step | Done when |
| --- | --- | --- |
| 17.1 | **Done 2026-10-23.** The app is called Easy Reader: the launcher label (`AndroidManifest.xml`), the title in the app bar and in `MaterialApp`, the iOS display name, the scan page's message and the User-Agent. Unchanged on purpose: the application id `io.github.jjomin.pdfreader`, the package name, the `pdfreader://` pairing address, and the Nextcloud folder `PDF Reader` (it is the place the synced documents are in, on the desktop too). ADRs and old plan rows keep the name they were written under. **The name.** | Device: seen ("Easy Reader" in the app bar, and in the accessibility tree). |
| 17.2 | **Done 2026-10-23.** What a screen reader sees was dumped from the phone (`uiautomator dump`): the PDF pages already give it the page number and each line of text (pdfrx), and the fast-scroll grip is a slider. Found: with a document open, the Home list and a second play bar were still in the tree, behind the reader. `BlockSemantics` on the reader and on the player now hides what they cover; the dump shows only the reader's own controls, and only the player's. The reading view marks headings and "Page N" as headings, so a screen reader can jump by them, and the page label's colour is the theme's secondary text colour (it was 50 % text colour, below contrast 4.5 in sepia). **Screen readers in the reader.** | Device: the accessibility tree seen in the reader and in the player. Not with TalkBack itself. |

CI fix (2026-10-23, after the first run on GitHub): three test files failed in `setUpAll`, because `flutter test`
finds no PDFium on Linux, and two of them read PDFs from the desktop's checkout, which a CI machine does not
have. `.github/actions/pdfium` fetches the pinned PDFium (checksummed) and sets `PDFIUM_PATH`; the synthetic
`sample.pdf` is copied into `test/fixtures/` (`test/fixtures_test.dart` fails when the desktop's differs);
the tests on the real document `centric` are skipped where the desktop checkout is missing (`skipWithout`,
or `DESKTOP_REPO=/nonexistent` to try it). Run as on the CI: 5 pass and 4 are skipped. Not yet seen green on
GitHub.


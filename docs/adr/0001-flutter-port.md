# 1. Flutter port: PDF engine, model delivery, text segmentation

Date: 2026-10-14

Status: **Accepted** by the owner on 2026-10-15.

## Context

The desktop app (`../pdfreader`, Electron, read-only reference) shows PDFs, lets the user mark and
comment, and reads aloud in German and English while tinting the spoken sentence and marking the
spoken word. This repository ports it to Flutter: Android first, tested on the owner's phone over
USB; iOS later on a MacBook, so the code stays iOS-ready but is not built for iOS now.

Fixed before this ADR (the owner's locked decisions):

- Speech runs through the official `sherpa_onnx` Dart package, the same runtime and models as the
  desktop (desktop ADR 2). Word timings come from the recogniser pass, with the word-length
  estimate as fallback.
- The raw-range model stays: a page's raw string is every text run concatenated in order, and the
  spoken sentence, the spoken word, marks, search hits and saved notes are offset ranges into it.
- `src/shared/` is ported to pure Dart in `lib/shared/`, with its unit tests case for case.
- Offline only. Out of scope: the XTTS GPU voice, the Windows installer, Pocket TTS.

Three questions follow from that and are decided here: which PDF package (1), how the speech
models reach the phone (2), and how the pure logic gets the two platform features it leans on
that Dart lacks (3). Section 4 lists every package this ADR asks to approve.

## 1. PDF package

### What the package must give

`layout.ts` turns text runs into paragraphs. Each run needs its string, position, height, font and
whether a line ends after it (`RawItem` in `src/shared/types.ts`). Highlights need a rectangle for
every character of the raw string. Both must come in content-stream order, the order the PDF draws
the text, because that is the reading order the desktop relies on (SPEC limit 3).

### Candidates

Checked on pub.dev on 2026-10-14. For pdfrx and pdfium_dart I also read the source
(`pdfrx_engine` 0.6.1, commit `42c8409`, 2026-10-05).

| | **pdfrx** 2.6.5 (`pdfrx_engine` 0.6.1) | **Syncfusion** `syncfusion_flutter_pdf` 35.1 + `_pdfviewer` | **Own binding** on `pdfium_dart` 0.3.1 |
| --- | --- | --- | --- |
| Engine | PDFium, the engine of Chrome's PDF viewer | Pure Dart parser for text; the viewer draws with the platform's renderer | PDFium |
| Text with char rects | `PdfPage.loadText()` returns `fullText` and one `charRects` entry per character. In the source it loops `FPDFText_GetUnicode` and `FPDFText_GetCharBox` over every PDFium char index, so the order is PDFium's text-page order, which follows the content stream. It includes the spaces and `\r\n` PDFium inserts. **Missing:** font size and font name per char, and the "generated" flag. | `extractTextLines()` gives line, word and glyph, each with bounds, font name and size. Whether lines come in stream order or sorted by position is **not documented** and was not tested. | Everything PDFium has: `FPDFText_GetFontSize`, `GetFontInfo`, `IsGenerated`, `GetTextObject`. Runs could be rebuilt almost like PDF.js items. |
| Rendering | PDFium in a background isolate, `PdfViewer` widget with pinch zoom, scrolling, text selection, links, and paint callbacks per page for our own overlays | Android's `PdfRenderer` and iOS PDFKit. Text boxes come from one engine and pixels from another, so marks can drift from the ink. | We would write the viewer: tiling, zoom, gestures, selection. Weeks of work. |
| Speed | Not measured. PDFium is the reference for speed; rendering is off the UI thread. | Not measured. Parsing a whole page in Dart is likely slower than PDFium. | Same as pdfrx. |
| Licence | MIT (PDFium itself BSD-3) | Commercial, or the free Syncfusion Community License with registration. The pub.dev page calls it "a commercial package". | MIT |
| iOS | Yes, through `pdfium_flutter` (PDFium XCFramework) | Yes | Android build hook only. iOS needs `pdfium_flutter` as well. |
| Network | `http` is a dependency, used only by `PdfDocument.openUri`. We never call it. | Not checked | Downloads PDFium at **build** time, from bblanchon/pdfium-binaries |

### Decision

**pdfrx.** It is the only candidate with a finished viewer, an open licence and per-character
rectangles from the same engine that draws the pixels. Syncfusion is out on its licence and its
two engines. The own binding gives better text data but costs us a viewer.

### How the raw string is made on the phone

PDF.js and PDFium split text differently, so the phone cannot reproduce the desktop's raw string
character for character. The mobile definition:

- Take PDFium's char stream from `loadText()`.
- Drop the `\r\n` pairs PDFium inserts at line ends. A run that ends before one gets
  `hasEOL = true`, which is how `layout.ts` sees a line end from PDF.js. PDF.js has no character
  there either.
- Keep everything else, including PDFium's inserted spaces between words (PDF.js inserts its own
  in the same places, mostly).
- Keep, for every raw offset, the PDFium char index it came from, so a raw range maps to
  `charRects` for painting.
- Cut runs at line ends and where the gap or the glyph height jumps. A run's height is the largest
  character box in it.

This lives in `lib/shared/` as a pure function from `(fullText, charRects)` to
`(items, charIndex)`, with tests. Everything downstream (`layout`, `utterances`, `search`, `notes`)
is the ported code and does not know which engine made the string.

### Consequences

- **Font names are not available through pdfrx.** `layout.ts` uses the font in two places: a
  short line in a font other than the body's is a heading ("titleLike"), and a font change with a
  wide gap starts a new block. Without it every run gets the same font, so those two rules never
  fire. Size and numbering still find most headings: the ported layout test's
  "2.1 Related Work" is caught by its number. The upgrade, if the comparison in PLAN step 1.6 shows
  missed headings: read `FPDFText_GetFontSize` and `GetFontInfo` through `pdfium_dart`, which
  pdfrx already depends on. PDFium must then only be called from pdfrx's worker isolate, which
  pdfrx does not export, so this means an upstream change or a careful fork. Not decided now.

  *Measured in step 1.6, 2026-10-15.* On the desktop's `sample.pdf` the phone's dump is identical
  to the desktop's. On a real seven-page IEEE paper (`centric_2026_1_10_30003.pdf`), 33 of 369
  desktop lines differ. The phone finds eight Roman-numeral section headings ("II. TUTORIAL QUALITY")
  that the desktop splits into "II." plus body text. It misses what the desktop finds through a
  font change: four italic subsection headings ("A. Experimental Design"), "REFERENCES" and two
  "APPENDIX" labels, which it joins to the paragraph after them. So the font upgrade is needed
  for parity; the owner decides when (PLAN step 1.14 report).
- **Glyph boxes, not font boxes.** `FPDFText_GetCharBox` is the tight box of the ink, so an "x" is
  shorter than an "H". *As built:* a run's size is the median height of its x-height letters
  divided by 0.5; a line without them (digits only) uses its capitals and digits, converted with
  the ratio of x-height to capital height measured on the page's own lines. The largest box, as
  first planned, split paragraphs wherever a line held a parenthesis. The run height above is therefore a cap height, about 0.7 of the font size.
  The layout rules compare sizes by ratio, which survives a constant factor; the absolute
  threshold `<= 0.7` between line sizes may need scaling. Measured in step 1.6.
- **Notes files do not carry over by offset.** A mark's `start` and `end` written by the desktop
  point into PDF.js's string, and the phone's string differs wherever the engines insert spaces
  differently. Both sides already store the marked text and re-find it by search when the offsets
  do not match (`reanchor`, desktop ADR 3). On the phone that search ignores whitespace, which the
  desktop's does not. So:
  - desktop to phone: a mark is found wherever its letters match;
  - phone to desktop: a mark is found where the two engines agree on spaces inside the marked
    text, and is otherwise kept in the file but not painted (the desktop never drops it, see
    `notes-panel.ts` `anchored`).

  How many marks survive each direction is measured in M2 on the fixture PDF. The file format does
  not change.
- PDFium extracts ligatures as their letters or as the ligature character, depending on the font's
  ToUnicode map. `layout` normalises per character (NFKC) and keeps the offset map either way.

## 2. How the speech models reach the phone

Sizes on disk, measured in the desktop's `models/` folder:

| Model | Files | On disk |
| --- | --- | --- |
| Kokoro multi-lang v1.0 (en) | 377 | 383 MB, of which `model.onnx` 311 MB. Chinese-only files (`dict`, `lexicon-zh.txt`, the `.fst` files) are 16 MB and can be left out. |
| Piper Thorsten high (de) | 359 | 126 MB, mostly `espeak-ng-data` |
| NeMo FastConformer CTC en-de-es-fr int8 (recogniser) | 6 | 127 MB |
| **Total** | | **636 MB**, about 620 MB without the Chinese files |

`sherpa_onnx` opens models by file path, so the files must sit as ordinary files in the app's
storage either way.

### Option A: inside the APK as Flutter assets

- APK about 700 MB (ONNX weights hardly compress) plus the app itself.
- Assets inside an APK are not files. On first start the app copies them out, so the phone holds
  them twice: about 1.3 GB.
- Every `flutter run` that changes the APK pushes about 700 MB over USB. That makes each try in
  development slow. Not measured; at typical USB 2 adb speeds it is around half a minute to a
  minute per install.
- Google Play would refuse it (the base module limit is far below this), so a later store release
  needs Play Asset Delivery, an App Bundle and a different build. Sideloading would work.
- Benefit: one file, nothing else to do.

### Option B: copied once into the app's own storage

- The app reads models from its app-specific folder,
  `/sdcard/Android/data/<app id>/files/models/` on Android, `Documents/models/` on iOS. Same
  folder names as the desktop and `models.json`.
- In development: `tool/push_models.ps1` runs `adb push` from a local `models/` folder (filled by
  `tool/fetch_models.dart` from the URLs in `models.json`, a build-time download, or copied from
  the desktop's folder by hand). About 620 MB once; afterwards `flutter run` installs only the
  app.
- For someone without adb: an "Import models" button that takes a folder through the system
  picker and copies it in. On iOS, the Files app or Finder file sharing into `Documents/models/`.
  This button is not in M1.
- APK estimated 40 to 80 MB per CPU architecture (the sherpa-onnx and ONNX Runtime libraries and
  PDFium). Measured at the end of M1.
- On the phone the models take 620 MB once.
- The folder survives app updates and reinstalls, but Android deletes it when the app is
  uninstalled.
- Without models the app opens PDFs and says which models are missing and where to put them.

### Decision

**Option B.** It keeps development fast, stores the models once, keeps the APK small, and is the
same on Android and iOS. Its cost is a one-time copy and a "models missing" screen.

The app never downloads at runtime. `tool/fetch_models.dart` runs on the PC.

## 3. Text segmentation and Unicode normalisation in pure Dart

`utterances.ts` splits sentences and words with `Intl.Segmenter`, and `layout.ts` expands
ligatures with `String.normalize('NFKC')`. Dart has neither. Its `RegExp` does support
`unicode: true` with `\p{L}`, `\p{Lu}`, `\p{Ll}`, lookahead and lookbehind, and Dart strings are
UTF-16 like JavaScript's, so offsets and the regular expressions port as they are.

- **Segmentation: write it.** `lib/shared/segment.dart` implements the Unicode sentence and word
  boundary rules (UAX #29), which is what `Intl.Segmenter` implements through ICU. The character
  property tables are generated by `tool/gen_unicode.dart` from the Unicode data files at
  development time and committed. Checked three ways:
  1. Unicode's own `SentenceBreakTest.txt` and `WordBreakTest.txt`.
  2. A golden file made by `tool/segmenter_golden.mjs`, a Node script using only built-ins, that
     runs `Intl.Segmenter` over a corpus of German and English sentences from the test cases and
     fixture text. The Dart segmenter must give the same boundaries and the same `isWordLike`.
  3. The ported `utterances` tests.

  ICU tailors a few word rules beyond UAX #29. Where the golden file disagrees with the Unicode
  tests, the golden file wins, because it is what the desktop does.
- **NFKC: `unorm_dart`** 0.3.3 (MIT, pure Dart, Unicode 18, all four forms). A full NFKC, not a
  ligature table, because PDFs also contain spacing accents, superscript digits and full-width
  forms that NFKC rewrites, and the offset map must stay identical to the desktop's.

Considered and not chosen: the `icu4x` Dart package (a Rust build per platform, much more than we
need) and Android's `BreakIterator` over a platform channel (not pure Dart, and the result would
depend on the phone's ICU version).

## 4. Packages to approve

Only these. Anything else gets asked for first.

| Package | Licence | Why |
| --- | --- | --- |
| `pdfrx` (with `pdfrx_engine`) | MIT | Section 1. `pdfrx_engine` directly, for the `tool/dump.dart` command line tool, which runs on Windows without Flutter. |
| `sherpa_onnx` 1.13.8 | Apache-2.0 | Locked decision. The same version the desktop pins. Its offline recogniser result has `tokens` and `timestamps`, which `align` needs. |
| `unorm_dart` | MIT | Section 3 |
| `audio_service` | MIT | Media notification, lock screen controls and the Android foreground service that keeps the Dart code running with the screen off. iOS: background audio and Now Playing. |
| `just_audio` | MIT | Plays each synthesised sentence (written as a WAV file to the cache folder) and reports the position that drives the word mark. |
| `path_provider` | BSD-3 (Flutter team) | The app's storage folders on both platforms |
| `integration_test`, `flutter_test`, `flutter_lints` | BSD-3 (Flutter SDK) | Tests on the phone, unit tests, lints. They come with `flutter create`. |

**Not a package: opening and saving documents.** `file_picker` copies the chosen file into the
cache on Android, which loses where it came from, and M2 must write `<file>.pdf.notes.json` next to
the PDF. So the app gets a small platform channel of its own (`DocumentAccess`, Kotlin now, Swift
later) on top of the system document picker. M1 needs only "pick a PDF and read it".

## What was not verified

- Nothing ran when this was written. *Since 2026-10-15 the toolchain is installed and the phone
  connected (PLAN, M0).*
- *Measured in step 1.8, 2026-10-15, on the owner's Galaxy S20 FE (SM-G780G, Snapdragon 865,
  6 GB, Android 13), debug build, models pushed with `tool/push_models.ps1` (621 MB):*

  | | Load | Seconds per second of audio | Recogniser |
  | --- | --- | --- | --- |
  | Piper Thorsten (de), 4 threads | 0.9 to 1.1 s | 0.50 to 0.55 | heard the sentence word for word |
  | Kokoro (en), 4 threads, short sentence | 1.8 to 2.4 s | 0.73 to 0.79 | heard the sentence word for word |
  | Kokoro (en), long mixed sentence, by threads: 2 / 3 / **4** / 6 / 8 | | 1.13 / 0.93 / **0.84 to 0.91** / 0.93 / 1.01 | |
  | Recogniser (NeMo CTC int8) | 1.0 to 1.2 s | about 0.03 (0.1 s per sentence) | 35 tokens with 35 times |

  Memory (RSS) with all three loaded: 1.45 GB, of which about 0.42 GB is the app and test
  harness before any model. Kokoro gets slower run after run as the phone warms. **Kokoro is
  over the 0.8 limit, so PLAN step 1.8 stopped here for the owner's decision.**
- Kokoro's speed on a phone. On the desktop's Ryzen it takes 0.32 seconds per second of audio
  (desktop ADR 2). A phone CPU is several times slower, so it may fall behind the voice. This is
  the first thing M1 measures (step 1.8). If it is too slow, the choices are a smaller English
  voice or reading with a longer lookahead. That decision goes back to the owner.
- Memory with Kokoro (311 MB of weights), Piper and the recogniser loaded together. Not known.
- Whether pdfrx's text order matches PDF.js's on real papers. Step 1.6 compares them. *Measured:
  the same reading order on both test files, including two columns. Font names: see section 1.*
- Whether the build works with a space in the project path (`Work Tilly`). Native builds with
  CMake sometimes break on spaces. If they do, the fix is a drive letter mapped to the folder with
  `subst`, not moving the repository. *2026-10-15: the template app builds and runs from this
  path. Packages with native code (sherpa_onnx, pdfrx) are still to be tried in M1.*
- pdfrx needs Dart 3.13 or newer (`pdfrx_engine` 0.6.1's `pubspec.yaml`), so the Flutter SDK must
  be a release that ships it.
- Syncfusion's line order and both engines' speed were not tested.

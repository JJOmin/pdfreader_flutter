# What the phone app does

The Android port of `../pdfreader`, at the end of M1 (2026-10-21). The plan is in
[PLAN.md](PLAN.md), the reasons in [adr/](adr/).

## Works

- **Prepared documents.** The home screen lists the documents the desktop prepared ("Add this
  document" in its Phone dialog), copied to the phone with `tool/push_library.ps1`. A PDF opened
  with **Open a PDF** is found in that library by the hash of its bytes, wherever it came from.
- **Reading aloud** with the desktop's audio (ADR 2). The phone builds its own sentences from
  PDFium's text. Where a page's words equal the desktop's, which was every page tested, it reads
  the desktop's sentences, placed on its own words by index. Elsewhere it matches sentences by
  their text and skips those with no match, and says how many.
- **Controls:** play and pause, previous and next sentence across pages, stop, and speed from
  0.6 to 2 with the pitch kept.
- **Highlighting:** the spoken sentence is tinted and the spoken word marked, painted from raw
  ranges onto PDFium's glyph boxes, one box per line. The view follows the voice at the user's
  zoom, unless the user touched it in the last three seconds.
- **Reading view:** the text alone, restyled: OpenDyslexic, Lexend, or the phone's own sans or
  serif; size, line and letter spacing; light, sepia or dark. Speech, the word mark and search work
  in it as on the pages, and switching keeps the page while the voice goes on.
- **Marks and comments** in both views: select text, choose highlight, underline or strike-through
  and one of four colours, and the mark is made. A tap on a mark opens its comment, and the Notes
  button lists every mark and the general notes. They are kept in the app, one file per document,
  in the desktop's notes format.
- **Search** in both views, also across a hyphenated line break.
- **Cloud sync** (the cloud icon): sign in to Nextcloud, the sync key from the desktop, a list of
  the documents the desktop put there, download of the ones chosen, and a sync of their place and
  marks. Only tried against a stand-in Nextcloud so far; Dropbox is built but not tried.
- **Wi-Fi sync** with a paired desktop: its prepared documents, and the place in both directions.
- **Screen off:** audio_service keeps reading in a media playback service, with a notification
  and lock screen controls.

## How it was checked

| Check                                                        | Result                                                                                                                                                                  |
| ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tool/check.ps1`                                             | Analyze, format and the unit tests pass.                                                                                                                                |
| `test/sync_golden_test.dart`                                 | Every page of `sample.pdf` and the 7-page paper gives the desktop's words and hash.                                                                                     |
| `integration_test/reader_test.dart` on the S20 FE            | Reads the pushed fixture: 5 sentences in 25 s, every word marked in order and inside its sentence. Next, previous and pause work.                                       |
| The same with `--dart-define=SCREEN_OFF=true`                | The shell turned the screen off for 20 s; the phone dozed, the media session said playing, and reading went on.                                                         |
| Screenshots during the test                                  | The tint and the word mark sit on the right letters at fit-to-width, including a sentence that starts mid-line and runs over a line break.                               |

## Known limits

1. **Only documents the desktop prepared are read aloud.** Others show "Not prepared on the
   desktop" and Play is off (ADR 2). The step 1.8 voices and `sherpa_onnx` are still in the APK,
   unused.
2. **Documents arrive over Wi-Fi** from a paired desktop (Desktops, then Sync), or over USB with
   `tool/push_library.ps1` after the app is installed: installing it the first time clears the
   folder. Sync runs when the user presses it, not in the background.
3. **Sentence joins are slower than on the desktop:** about 300 ms between sentences, against
   80 ms. Each sentence has its own preloaded player, and the player reports the end 200 to 280 ms
   after the audio's length. Marked `// shortcut` in `lib/reader.dart`: if the owner hears it as too
   slow, play one gapless just_audio playlist with silences instead.
4. **Not verified on the device:** the highlight at 300 % zoom, two minutes with the screen off,
   and the notification's buttons. These are left for the owner.
5. **Marks are synced with the desktop on each sync, merged per mark** (step 5.7): marks new on
   either side are kept, the later edit of a mark wins, a mark deleted on either side stays
   deleted, and the later general notes win. Times are the two devices' own clocks. Marks are
   found again on the other device by their text, since the two engines' offsets differ. Only
   documents the desktop prepared are synced, and only when the user presses sync.
   In the reading view a mark cannot span two paragraphs, because each paragraph is selected on its
   own; in the PDF it can span lines and pages (one mark per page).
6. **The place and the speed are remembered** (step 4.1), and a prepared document's place goes to
   the desktop on each sync (step 5.6). The phone's zoom is pdfrx's, not the desktop's, so only
   the page, the offset and the sentence are shared.
7. **Previous on a page's first sentence** goes to the previous page's last sentence. The desktop
   goes to the last sentence of the same page, which is a bug in its `reader.ts`.

## Size

Release APK, all ABIs: **142 MB** (`flutter build apk --release`, 2026-10-21). Most of it is
probably the unused `sherpa_onnx` and its ONNX runtime for every CPU type; this was not broken
down. `--split-per-abi` or removing `sherpa_onnx` (ADR 2 leaves that decision open) would shrink it.

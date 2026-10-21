# PDF Reader (Flutter)

The Android and iOS port of the desktop app in `../pdfreader`. It shows PDFs, lets the user mark
and comment, and reads the text aloud while highlighting the spoken sentence and word. German and
English. No cloud: the text and the voices stay on the user's own devices.

What to build next is in [docs/PLAN.md](docs/PLAN.md). Why is in [docs/adr/](docs/adr/). The
desktop repository is the reference: read it, never change it from here. Its `docs/WORKFLOW.md`
describes how we work, and it applies here too.

## Commands

| Command                                         | Use                                                             |
| ----------------------------------------------- | --------------------------------------------------------------- |
| `powershell -ExecutionPolicy Bypass -File tool/check.ps1` | Analyze, format check, unit tests. Run before "done". |
| `flutter run`                                   | Runs the app on the connected phone with hot reload.            |
| `flutter test integration_test --no-uninstall`  | Drives the real app on the phone. Run after UI or speech work.  |
| `flutter build apk --release`, then `adb install -r build/app/outputs/flutter-apk/app-release.apk` | Updates the installed app and keeps its documents and pairings. `flutter install` uninstalls first, which deletes them. |
| `flutter devices`, `adb devices`                | Is the phone connected and authorised?                          |
| `powershell -File tool/push_models.ps1`         | Copies the speech models to the phone (621 MB, once).           |

Always pass `--no-uninstall` to `flutter test` on the phone. Without it Flutter uninstalls the
app afterwards, and Android deletes the pushed models with it.

## Layout

- `lib/shared/` Pure Dart, no Flutter imports, ported from the desktop's `src/shared/`. Every
  file has a test in `test/shared/` that keeps the TypeScript test's names, inputs and outputs.
- `lib/` outside `shared/`: widgets, the speech isolate, platform channels.
- `android/`, `ios/` Platform code. `DocumentAccess` (open and save documents) lives here as a
  platform channel, Kotlin now and Swift later.
- `tool/` Scripts run on the PC, never in the app.
- `models/` Speech models, not in git. They reach the phone with `tool/push_models.ps1`.

## The one idea to keep intact

A page's **raw string** is the page's text runs concatenated in order. A `RawRange` is a span of
offsets into it. The spoken sentence and word, the user's marks, saved notes and search matches
are all raw ranges. On the phone the raw string comes from PDFium's char stream, with the `\r\n`
it inserts at line ends dropped, and every raw offset keeps the PDFium char index it came from,
so a range can be painted on `charRects` (ADR 1). Do not introduce a second coordinate system,
and do not add a feature to one view only.

## Rules

- Follow `docs/PLAN.md` step by step. Each step has a "done when": show that it holds. Stop for
  review at the end of each milestone.
- Smallest change that fully solves the task. Only the packages approved in ADR 1, 2 and 3. Ask before
  adding any other.
- New logic goes in `lib/shared/` with a test written first. A bug gets a failing test before
  the fix.
- No internet at runtime: no cloud voices, no external models or LLMs, no downloads. Speech is
  made on the user's desktop. For now the phone has no voice of its own and plays only prepared
  audio (ADR 2). The only network uses are sync with the user's paired desktop on the local network
  (ADR 2), and with the user's own Nextcloud or Dropbox after they signed in, as encrypted files
  (ADR 3).
- Comments explain why, not what. A known limit is marked `// shortcut: <limit>, <when to upgrade>`.
- Do not claim something works on the phone without running it there. If no phone is connected,
  report the step as **not verified on device**.
- Keep iOS buildable in principle: no Android-only API outside `android/` and platform channels.

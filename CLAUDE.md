# PDF Reader (Flutter)

The Android and iOS port of the desktop app in `../pdfreader`. It shows PDFs, lets the user mark
and comment, and reads the text aloud while highlighting the spoken sentence and word. German and
English. Nothing leaves the phone.

What to build next is in [docs/PLAN.md](docs/PLAN.md). Why is in [docs/adr/](docs/adr/). The
desktop repository is the reference: read it, never change it from here. Its `docs/WORKFLOW.md`
describes how we work, and it applies here too.

## Commands

| Command                                         | Use                                                             |
| ----------------------------------------------- | --------------------------------------------------------------- |
| `powershell -ExecutionPolicy Bypass -File tool/check.ps1` | Analyze, format check, unit tests. Run before "done". |
| `flutter run`                                   | Runs the app on the connected phone with hot reload.            |
| `flutter test integration_test`                 | Drives the real app on the phone. Run after UI or speech work.  |
| `flutter devices`, `adb devices`                | Is the phone connected and authorised?                          |

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
- Smallest change that fully solves the task. Only the packages approved in ADR 1. Ask before
  adding any other.
- New logic goes in `lib/shared/` with a test written first. A bug gets a failing test before
  the fix.
- Everything runs offline. No network calls at runtime. Downloads happen in `tool/` on the PC.
- Comments explain why, not what. A known limit is marked `// shortcut: <limit>, <when to upgrade>`.
- Do not claim something works on the phone without running it there. If no phone is connected,
  report the step as **not verified on device**.
- Keep iOS buildable in principle: no Android-only API outside `android/` and platform channels.

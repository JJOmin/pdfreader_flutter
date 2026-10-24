# Easy Reader (Flutter)

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

On the Mac, Flutter comes through FVM: prefix `flutter` and `dart` with `fvm`, and run
`tool/check.sh` instead of `tool/check.ps1`. It also points the PDFium tests at the library
Flutter's build downloaded. The other `tool/*.ps1` scripts need PowerShell (`pwsh`) there. The desktop checkout called `../pdfreader`
throughout these docs is `../pdfReaderWindows` on the Mac.

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
  The recogniser instead comes with the app: `tool/bundle_recogniser.sh` puts it into
  `assets/recogniser/` before a build (ADR 7).

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
- Smallest change that fully solves the task. Only the packages approved in ADR 1, 2, 3 and 4. Ask before
  adding any other.
- New logic goes in `lib/shared/` with a test written first. A bug gets a failing test before
  the fix.
- No internet at runtime: no cloud voices, no external models or LLMs, no downloads. Speech is
  made on the user's desktop, and that audio is always preferred. Where it is missing, the phone's
  own offline text-to-speech reads instead (ADR 5). Spoken comments are recognised on the phone by sherpa-onnx (ADR 6). The only network uses are sync with the user's paired desktop on the local network
  (ADR 2), and with the user's own Nextcloud after they signed in, as encrypted files
  (ADR 3).
- Comments explain why, not what. A known limit is marked `// shortcut: <limit>, <when to upgrade>`.
- Do not claim something works on the phone without running it there. If no phone is connected,
  report the step as **not verified on device**.
- Keep iOS buildable in principle: no Android-only API outside `android/` and platform channels.
- **Branches and CI.** A feature is made on a `feature/<name>` branch, never on `main`; it reaches `main`
  through a pull request whose CI (`.github/workflows/ci.yml`: analyze, format, tests, a release
  build) is green. Check `git branch --show-current` before the first edit of a feature. Do not commit
  or push unless asked. When the owner pushes a `feature/...` branch, `auto-pr.yml` opens a draft pull
  request to `main` and starts the CI; "Ready for review" is the owner's click. A release is a `v*` tag, built and signed by `release.yml`; it needs the
  owner's keystore in the repository's secrets and refuses to publish a debug-signed app.
- **Security and accessibility are part of "done".** `SECURITY.md` has what is guarded and why: do not
  weaken it (backup off, no `file:` access to the app's own storage, pinned TLS, no new permission
  without the owner). A new screen passes `test/accessibility_test.dart`'s guidelines (48 dp touch
  targets, a label on every control, text contrast of 4.5) in every theme.

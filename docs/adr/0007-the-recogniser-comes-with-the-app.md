# 7. The speech recogniser comes with the app

Date: 2026-10-24

Status: **Accepted** by the owner's choice of 2026-10-24, among bundling it, sending it from the
paired desktop, or both.

## Context

Spoken comments are recognised on the phone (ADR 6, section 5), but the model reached the phone only
through `tool/push_models` and a cable. A phone set up from the release page had no dictation.

## Decision

1. **The APK carries the recogniser**: `model.int8.onnx` and `tokens.txt` of the multilingual NeMo
   CTC model (126 MB), as Flutter assets in `assets/recogniser/`.
2. **Not in git**, like every speech model. `tool/bundle_recogniser.sh` fills the folder before a
   build: from the desktop's models folder when it has the model, else from sherpa-onnx's release,
   the address the desktop's `models.json` names. Both files must match checksums written in the
   script. The CI and release workflows run it, so every published APK has the model. A build without
   it still works, and dictation says the model is missing.
3. **Copied out once.** sherpa-onnx reads a model from a file path, and an asset is not a file. On the
   first use of dictation the two files are written to the app's private support folder
   (`lib/speech/model_files.dart`, `unpackBundled`); a marker written last tells a whole copy from one
   that was cut off.
4. **A pushed model still comes first**, so a newer one can be tried with `tool/push_models` without
   a new build.

## Consequences

- The APK grows from about 165 MB to about 290 MB, and the phone keeps a second copy of 126 MB after
  the first dictation.
- The first dictation after installing waits a few seconds for the copy.
- No network at runtime: the model is downloaded only on the build machine, never by the app.
- The voices (Kokoro, Piper) still come from the desktop or `tool/push_models`; the phone's own
  voice reads where they are missing (ADR 5).

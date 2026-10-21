# 2. Audio prepared on the desktop

Date: 2026-10-21

Status: **Accepted** by the owner on 2026-10-21, with the packages and permissions of section 5,
and with the phone's own voice turned off for now (section 1). The library, the protocol and the
pairing are decided in the desktop's ADR 7 (`../pdfreader/docs/adr/0007-phone-sync.md`). This ADR
covers only what the phone does.

## Context

Kokoro is too slow to read live on the phone: 0.84 to 0.91 seconds per second of audio (ADR 1,
PLAN step 1.8). The desktop prepares a document's audio with Kokoro or XTTS-v2. The phone fetches
the audio, the word timings and the PDF over the local network, and both devices share the place
where reading stopped.

## Decision

### 1. Prepared audio is the only source of speech

The owner decided that, for now, the phone has no voice of its own. The speech service of step 1.9
plays only what the desktop prepared.

- **A sentence whose sync key is in the index is played.** The key is the sentence text after NFKC
  and whitespace folding, hashed, as in desktop ADR 7 section 3. Such a sentence is ready at once:
  no synthesis and no recogniser pass. Its word timings come from the index when the word count
  matches, otherwise from `estimateTimings`.
- **A sentence with no match is skipped.** The document shows how many of its sentences have no
  audio.
- **A document with no library opens and can be read on screen.** Play is off, and the app says
  "Not prepared on the desktop".

The queue of two sentences ahead, its order and its cancellation on seek stay as they are. The
phone still builds its sentences from its own raw string, so marks, search and the highlight keep
the single coordinate system.

The step 1.8 code and `sherpa_onnx` stay in the repository, unused. Removing them, which would
shrink the APK, is a separate decision. Pushing the models (`tool/push_models.ps1`) is no longer
needed to read.

### 2. Playback

`just_audio` plays the `.opus` files. On Android it uses ExoPlayer, which reads Ogg Opus. The
reading speed is applied with `setSpeed`, keeping the pitch, because the audio is rendered at 1.0.

### 3. Storage

Downloaded documents live in the app's own storage (`path_provider`), in the same layout as the
desktop's library. They open from there, without `DocumentAccess`. Each one can be removed from the
phone. The place is written to `state/<this device>.json` and sent with `PUT` when the desktop can be
reached.

### 4. Network

- **Discovery.** UDP through `RawDatagramSocket`. Android drops multicast unless the app holds a
  `MulticastLock`, so a small `Discovery` platform channel in Kotlin takes the lock while the
  "Desktops" screen is open. A typed address works without it.
- **Requests.** `HttpClient` from `dart:io`. Its `badCertificateCallback` accepts a certificate
  only when its SHA-256 matches. During pairing it must match the typed code. After pairing it must
  match the pinned fingerprint. The token is kept in the app's own storage.
- **iOS, later.** Listening to multicast needs Apple's multicast entitlement, which Apple grants on
  request. The system also asks the user for local-network access. Until then, a typed address
  works.

### 5. Packages and permissions

| What                                | Why                                                                                                                                                                           |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `crypto` (Dart team, BSD-3)         | SHA-256 for the sync key and the certificate pin. It is already in `pubspec.lock` as an indirect dependency, so it adds no new code, but naming it directly needs approval. |
| `INTERNET`                          | Android needs it for any socket, local ones too. The rule in `CLAUDE.md` limits what the code connects to: paired desktops only.                                              |
| `CHANGE_WIFI_MULTICAST_STATE`       | For the `MulticastLock`. A normal permission: no prompt.                                                                                                                      |

## Consequences

- Reading uses less battery and starts at once, because there is no model to load.
- A sentence that PDFium and PDF.js split differently is not read. Step 5.1 measures how often
  that happens, and that number decides whether the design holds.
- A PDF the desktop has not prepared cannot be read aloud on the phone.
- Step 1.8's question, which on-device English voice to use, is set aside until the phone gets a
  voice of its own again.
- The release APK asks for `INTERNET`, which shows up as "network access" in the Play Store listing.

## Not verified

- The sentence match rate on real papers (step 5.1).
- That ExoPlayer plays the desktop's Ogg Opus files and that their word timings line up (steps 1.9
  to 1.11).
- Multicast on the owner's router and phone (step 5.3).

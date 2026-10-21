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

- **A prepared page whose words agree is read with the desktop's sentences** (desktop ADR 7
  section 3, chosen by the owner after the measurement below). The phone computes the page's words
  from its own raw string and compares their count and hash with the index. When they agree, each
  sentence of the index becomes a raw range from its first to its last word on the phone. Audio and
  word timings come straight from the index. Such a sentence is ready at once: no synthesis and no
  recogniser pass.
- **A page whose words differ** falls back to matching the phone's own sentences by their sync key:
  the text after NFKC and whitespace folding, hashed. A sentence with no match is skipped, and the
  document shows how many it skips.
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
- On a prepared page the phone tints sentences where the desktop breaks them, which can differ
  from its own layout near headings. Only on a page whose words differ is a sentence not read.
- A PDF the desktop has not prepared cannot be read aloud on the phone.
- Step 1.8's question, which on-device English voice to use, is set aside until the phone gets a
  voice of its own again.
- The release APK asks for `INTERNET`, which shows up as "network access" in the Play Store listing.

## Measured: the sentence match (step 5.1, 2026-10-21)

Both dump tools ran on every page: the desktop's `scripts/dump-text.ts` and this repository's
`tool/dump.dart`. A phone sentence counts as matched when its text, after NFKC and whitespace
folding, is among the desktop's sentences of the same file.

| File                                                                 | Desktop sentences | Phone sentences | Matched          | Words, desktop / phone       |
| -------------------------------------------------------------------- | ----------------- | --------------- | ---------------- | ---------------------------- |
| `tests/fixtures/sample.pdf` (German and English, 2 pages)            | 17                | 17              | 17 (100 %)       |                              |
| `docs/sample_pdfs/centric_2026_1_10_30003.pdf` (English paper, 7 pages) | 355               | 349             | **323 (92.6 %)** | 4,953 / 4,953, same sequence |

**Below the 98 % bar, so the step stopped for the owner's decision.** The owner chose to take the
desktop's sentence breaks by word index (section 1). Compared page by page, every page of both
files has the same words on both sides (sample: 98 and 67, paper: 728, 853, 809, 767, 737, 730 and
329), so with that design every sentence of both files has its audio.

Every miss comes from where a sentence starts and ends, never from the text itself. The two word
streams are identical, word for word. The 26 misses are all at the edges of blocks:

- **Section headings.** The desktop joins "I. INTRODUCTION" to the first sentence, and the phone
  keeps it apart. For subsection headings ("A. Experimental Design") it is the other way round.
  Each heading costs two sentences: the heading and the sentence next to it.
- **Roman numerals** ("II.", "VI."). The desktop reads them as a sentence of their own, and the
  phone keeps them with the heading.
- **A table header, a figure caption, a bullet and the reference list's heading.** These are joined
  on one side and split on the other.

These are the font-based heading differences recorded in ADR 1 section 1. The two engines give
different font information, so `layout` draws block edges differently.

This file has no German body text with hyphenation across lines, so German was checked only on
`sample.pdf`.

## Not verified

- The sentence match rate on a real German paper.
- That ExoPlayer plays the desktop's Ogg Opus files and that their word timings line up (steps 1.9
  to 1.11).
- Multicast on the owner's router and phone (step 5.3).

# 3. Nextcloud and Dropbox on the phone

Date: 2026-10-21

Status: **Accepted** by the owner on 2026-10-21, with all the recommendations of section 7: the
`cryptography` package, the custom scheme for Dropbox, a `SecretBox` channel of our own, and both
services built against stand-ins first, the real accounts tried at step 6.6. The design of the
store, its formats and the desktop's side are in the desktop's ADR 8
(`../pdfreader/docs/adr/0008-sync-through-a-store.md`, accepted, desktop half built). This ADR is
the phone's half that ADR 8 asks for.

## Context

Over Wi-Fi (ADR 2) the phone can sync only while it and the desktop are on the same network. ADR 8
lets the desktop put its prepared documents and its place in the owner's own Nextcloud or Dropbox,
encrypted before it leaves the computer. Until the phone can read that store, none of it reaches the
phone. The phone must also write back: its place, and its marks and comments (desktop ADR 7
section 1), so that reading and marking continue on either device from anywhere.

The offline rule in `CLAUDE.md` already allows the desktop to talk to the user's own Nextcloud or
Dropbox after sign-in. It has to say the same for the phone (section 6).

## Decision

### 1. What the phone does with the store

The phone is one more client of the same files as the desktop, with no logic on the other side:

- **Reads** a document: the manifest first, then the PDF, each page's index and each page's audio
  pack, into the same local library layout as ADR 2 section 3, so that everything after the
  download is unchanged. A pack is cut into the per-sentence `.opus` files. The manifest is written
  last, as on the desktop, so a folder with a manifest is a whole document.
- **Writes** its own place, `state/<device>.json`, and reads the other devices'.
- **Exchanges notes** by reading the store's `notes.json`, merging it with its own per mark (desktop
  ADR 7 section 1) and writing the result back. This needs the desktop to do the same, a step the
  desktop's plan does not have yet (section 5, step S8b). Where two devices write at the same time
  the last write wins for that moment, and the next sync merges again, since the merge loses
  nothing that either side still holds.
  `// shortcut: no If-Match or revision check on the notes file. Upgrade if a lost update is seen.`
- **Chooses what to download.** A document in the store is listed with its name, pages and size
  from the manifest, and downloaded when the user taps it, because the phone may be on mobile data
  and an hour of speech is about 11 MB. A document already on the phone is only updated.

### 2. The formats are the desktop's, unchanged

`PRS1`, a random 12-byte IV, then AES-256-GCM with the file's path as authenticated data. The
audio pack of ADR 8 section 3. The key as 64 hex digits, entered by the user once (a QR code can
carry it later). Paths built only from hashes and numbers and checked by `assertPath`. The server
address rules of `parseServerUrl`: https, or http only for the user's own network.

All of it is ported to `lib/shared/` with the desktop's test cases and golden files: a file sealed
by the desktop is opened by the phone and the other way round, byte for byte.

### 3. AES-GCM: a package or the platform

Dart's `crypto` (approved in ADR 2) has hashes but no AES. Two ways:

| Option                                    | For                                                                                          | Against                                                                                                |
| ----------------------------------------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| **A. The `cryptography` package** (MIT)   | Pure Dart, so it runs in `flutter test` on the PC and the desktop's golden files can be used. The same code on iOS later. | One new direct dependency. Pure Dart AES is slower than native: a page's pack of a few hundred KB takes well under a second, an hour of speech about 11 MB takes seconds. |
| **B. A platform channel to the system's** `javax.crypto` (Kotlin now, CryptoKit on iOS later) | No dependency. Native speed.                                          | Cannot run in `flutter test`: the golden files could only be checked on the phone. One more channel and a second implementation for iOS. |

**Recommendation: A**, because the whole point of the formats is that two programs agree on every
byte, and that is only checked cheaply where the tests run on the PC.

### 4. Signing in

- **Nextcloud.** Login Flow v2 as on the desktop: `POST <server>/index.php/login/v2`, open the
  returned `login` address in the system browser, poll the returned endpoint with `HttpClient`
  until the user approves. Both addresses must stay on the server the user typed. The result is an
  app password the user can revoke in Nextcloud. Opening the browser needs a few lines in
  `MainActivity.kt` (`ACTION_VIEW`), no package.
- **Dropbox.** The authorization code flow with PKCE and a refresh token, the app's own folder
  ("App folder" access) and no secret in the app, as on the desktop. The one open question is where
  the browser sends the user back to:

  | Redirect                                                                             | For                                                                           | Against                                                                                          |
  | ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
  | **A custom scheme**, `io.github.jjomin.pdfreader:/oauth`, handled by an intent filter | Android returns to the app by itself, also if it was stopped while the browser was open. | The owner adds a second redirect address to the Dropbox app (the desktop's is `http://127.0.0.1:53682/`). |
  | The desktop's loopback address, with a listener in the app for the sign-in               | One registered address for both.                                           | The app must stay alive and listening while it is in the background behind the browser.           |

  **Recommendation: the custom scheme.** The app key is the desktop's, and the owner still has to
  register the Dropbox app (desktop ADR 8 section 5) before either side can sign in.

### 5. Where the secrets are kept, and the sync key

The app password or refresh token, and the sync key, are secrets. On the desktop `safeStorage` seals
them with the operating system. On Android the equivalent is a key in the Android Keystore that never
leaves the chip.

| Option                                                  | For                                           | Against                                  |
| ------------------------------------------------------- | --------------------------------------------- | ---------------------------------------- |
| **A. A small `SecretBox` platform channel** in Kotlin     | No dependency. About forty lines: a Keystore AES key, secrets encrypted with it and written to the app's storage. | One more channel, a Swift version for iOS later. |
| B. The `flutter_secure_storage` package                  | The same Keystore underneath, ready made.     | A new dependency for what A does in forty lines. |

**Recommendation: A**, in line with `DocumentAccess` and the discovery channel.

Signing out forgets the sign-in and keeps the key, as on the desktop. The store's files are not
deleted. The sync key is shown on the desktop and typed or pasted on the phone: a wrong key is told
by the first file that fails to open, with the desktop's message.

### 6. The offline rule

`CLAUDE.md` is brought in line with the desktop's: the only network uses are sync with the user's own
paired desktop on the local network, and with the user's own Nextcloud or Dropbox after the user
signed in, as encrypted files. The code that talks to the network lives in `lib/` outside `shared/`,
as `desktop_link.dart` does. `INTERNET` is already in the manifest (section 5 of ADR 2), and no
further permission is needed.

### 7. What the owner decided

1. AES-GCM: the `cryptography` package.
2. Dropbox's way back to the app: the custom scheme `io.github.jjomin.pdfreader:/oauth`.
3. Secrets: a `SecretBox` channel of our own.
4. Both services are built against stand-ins first. The real accounts are tried at the end.

### 8. The steps

Each step has its own test first, with the desktop's cases.

| #   | Step                                                                                                                                              | Done when                                                                                                                                                                       |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 6.1 | This ADR, accepted 2026-10-21.                                                                                                                    | The owner has decided section 7, and `CLAUDE.md`'s rule matches the desktop's.                                                                                                  |
| 6.2 | `lib/shared/sync_store.dart`: `seal`, `unseal`, the pack, the key, `assertPath`, `parseServerUrl`, the paths. `SecretBox` if chosen.               | The desktop's golden files open and the phone's are opened by the desktop's code, byte for byte.                                                                                |
| 6.3 | The WebDAV store and the Nextcloud sign-in, with in-memory stand-ins written from Nextcloud's documentation, as on the desktop.                    | Unit tests pass against the stand-in: sign-in, list, get, put, and a refused path.                                                                                              |
| 6.4 | The Dropbox store and sign-in, the same way.                                                                                                      | Unit tests pass against the stand-in, including a refreshed token and a pause after a 429.                                                                                      |
| 6.5 | A "Cloud" screen: sign in, the key, the documents in the store, download with progress, and the exchange of place and notes. The desktop's S8b. | A document prepared on the desktop and sent to the store is downloaded on the phone, read, and its place and a mark made on the phone reach the desktop, all through the store. |
| 6.6 | A run against a real Nextcloud and a real Dropbox, on the device. **Stop for review.**                                                            | Recorded in "Not verified" below.                                                                                                                                               |

The desktop's S8a is this ADR's counterpart there: nothing, because ADR 8's engine already writes
what the phone reads. S8b is the notes exchange through the store.

## Consequences

- The phone reads and marks anywhere it can reach the owner's service, with the desktop off.
- One new dependency if option A of section 3 is chosen, and one or two small platform channels.
- Mobile data can be used for a download. The list shows sizes first, and nothing downloads
  without a tap.
- The phone still reads only documents the desktop prepared (ADR 2).

## Not chosen

- **A server of ours.** The owner does not want one (desktop ADR 8).
- **Dropbox's official SDK for Flutter.** It would add a large dependency and a secret-bearing flow
  for what the HTTP API and PKCE do directly.
- **Syncing every document automatically.** On mobile data that is a bill, so downloads are chosen.

## Built, 2026-10-21 (steps 6.2 to 6.5)

- Formats: the desktop's golden files, written by its own `seal` and `packAudio`, open on the phone,
  and the phone writes the same bytes as the desktop for the same IV.
- Stores and sign-ins: 30 tests against stand-in servers. A 600 KB file, the size of a page's audio
  pack, goes through both byte for byte.
- The engine: 21 tests against a whole store that the desktop's own engine filled (the prepared
  sample, its place, its notes).
- On the phone, in `integration_test/cloud_test.dart`: the Keystore box round trips, and the Cloud
  screen signs in to a stand-in Nextcloud on the PC over Wi-Fi, takes the key, downloads the sample
  in about 0.7 s, brings the desktop's notes and place down, and sends a mark that the desktop's
  code opens with the same key. Three runs in a row against one server.
- The desktop's counterpart, step S8b: its engine now exchanges `notes.json` through the store.

## Not verified

- Against a real Nextcloud and a real Dropbox account, both sign-ins. Until 6.6 only the stand-ins
  are tested, which prove agreement with our reading of the documentation, not with the services.
  The Dropbox sign-in has not been run on the phone at all: it needs the owner's registered app key
  (`--dart-define=DROPBOX_APP_KEY=…`) and the redirect `io.github.jjomin.pdfreader:/oauth` added to
  that app.
- That Android returns from the browser to the app through the custom scheme on the owner's phone.
- That the owner's Nextcloud accepts files of this size through its web server's upload limit.
- How long pure Dart takes to open an hour of prepared speech on the owner's phone (option A).

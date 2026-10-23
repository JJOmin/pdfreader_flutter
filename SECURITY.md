# Security

How the phone app protects the user's documents, and what was checked. The desktop app has its own
`SECURITY.md` in `../pdfReaderWindows`; the two talk to each other, so a change to one side's pairing
or sync is read against both.

## Reporting a problem

Open a private security advisory on the repository (Security, Report a vulnerability), or write to the
owner. Please do not post a vulnerability in a public issue.

## What the app holds and where it goes

Documents, notes, the voices' audio and the place in each document stay in the app's own storage.
Nothing is sent anywhere except to the user's own computer on the local network (ADR 2) and to the
user's own Nextcloud as encrypted files (ADR 3). No analytics, no cloud voices, no downloads of code.

## What guards it

| Where | What |
| --- | --- |
| Pairing with the computer | HTTPS to a self-signed certificate; no root is trusted, and every certificate is checked against the SHA-256 the user confirmed by code or QR (`desktop_link.dart`). A token of 256 bits follows. |
| Nextcloud | HTTPS only (HTTP only for a private address); the sign-in is the browser's Login Flow v2, so the app never sees the password, and its addresses must stay on the server the user typed (`store/nextcloud_login.dart`). |
| Files in the store | AES-256-GCM, a fresh IV each time, the file's path signed in, so a file moved to another path does not open (`shared/sync_store.dart`). |
| Secrets (sync key, app password) | Encrypted with a key in the Android Keystore, which never leaves the chip (`MainActivity.kt`). |
| Names from other devices | Document ids, device ids and file names are matched against strict patterns before they become a path, a key or a file name. |
| Backup | Off (`android:allowBackup="false"`): `adb backup` and the system's cloud backup cannot carry the documents away. |
| Other apps | `file:` addresses into the app's own storage are refused, so an intent from another app or a web page cannot make the app read its own private files; a document over 300 MB is refused. |
| Permissions | Network, multicast (finding the computer), a media service, and the microphone, asked for the first time the user dictates. |
| Release | Signed with the owner's key from `android/key.properties` or the CI's secrets; a build without it is signed with the debug key, says so, and cannot be published by `release.yml`. |

## Checked on 2026-10-23

A review of the manifest, the platform code, the pairing and sync code and the dependencies. Fixed:

1. **Backup was on** (the default): documents and notes could be taken with `adb backup`. Now off.
2. **A `file:` intent into the app's own storage was read.** Now refused (`MainActivity.isOwnPrivateFile`),
   checked on a phone with an intent aimed at the app's settings file.
3. **A document of any size was read into memory.** Now capped.
4. **Release builds were signed with the debug key**, in `build.gradle.kts`. A release key is now used where
   one is given, and the release workflow refuses to publish without it.

Not a problem, and why: the audio service and the media-button receiver are exported because Android's
media controls need them (`audio_service`); the app has no cleartext traffic (Android blocks it for this
target); the platform channels are reached only by the app's own Dart code.

## Open, for the owner

- **Create the release key** (`keytool -genkeypair -v -keystore release.jks -keyalg RSA -keysize 2048
  -validity 10000 -alias pdfreader`), keep it and its passwords somewhere safe outside the repository,
  put them in `android/key.properties` and in the repository's secrets (`release.yml` lists the names).
  Losing it means a new app cannot update the installed one.
- **Switch on, in the repository's settings:** branch protection for `main` (require a pull request and
  the CI's `check` job), secret scanning with push protection, and Dependabot alerts.
- A pairing request from the local network shows the other side's name and waits for the user's yes:
  the name is not proof of who asks. The QR code is the safe way, and the one that needs no click.

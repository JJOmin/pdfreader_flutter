# 4. Sync 2 on the phone

Date: 2026-10-22

Status: **Accepted**. The design is the desktop's ADR 10
(`../pdfReaderWindows/docs/adr/0010-sync-2.md`, accepted 2026-10-22); this ADR records the phone's
side where the phone had to choose, and the one package it adds.

## The package

`mobile_scanner` (BSD-3), for "Scan to pair" (step 7.6). The owner approved it on 2026-10-22 in
choice 3 of the desktop's ADR 10: CameraX with the bundled ML Kit model on Android, the system's
Vision on iOS, no network request. The camera permission is declared by the package and asked when
the user opens "Scan to pair", not at start. A refusal leaves the typed code, which still works.

## Where the phone chose

- **The memo.** The phone keeps, in `sync-memo.json`, the other devices' journals as last read (with
  their ETags), its own journal, and a hash of the notes and place it last exchanged per document.
  It is local, not an interchange format; the desktop keeps the same in its own file. A lost or
  damaged memo only makes the next sync walk the whole store.
- **The place is not a change.** The phone sends a mark 5 seconds after it was made, but a place
  goes with the next 30-second poll, so turning pages sends nothing by itself. (The desktop sends a
  place at most once a minute.)
- **Cloud documents.** An incremental sync does not list the cloud, so the phone keeps a catalog of
  manifests (`cloud-catalog.json`): a full walk replaces it, journals add to it.
- **Automatic downloads.** Updates the phone starts on its own wait for a network that is not metered;
  a tap always downloads.
- **Not yet.** Documents offered by a paired computer over Wi-Fi are not in the library list until
  steps 7.7 and 7.8.

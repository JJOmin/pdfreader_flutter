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
- **Offers travel in the journal.** Away from home a "Send to phone" offer is read from the desktop's
  change journal, which the phone polls anyway, not from a separate `inbox/<device>.json`: an offer
  costs no extra request. The phone cannot write the desktop's journal, so a decline made away from
  home is only remembered on the phone (`offers.json`) until it is next on the desktop's Wi-Fi.
- **Automatic Wi-Fi syncs fetch nothing new.** They keep up to date what is on the phone; a new
  document comes by the user's tap, an accepted offer, or the Sync screen's button.
- **Audio page by page (desktop ADR 11).** A document can be on the phone before any of its audio:
  the manifest of version 2 names the pages that have it, and a download fetches only the pages the
  phone lacks. The reader reads those pages and shows the others as a plain PDF.
- **PDFium for "Save PDF" (2026-10-23).** `pdfium_dart` and `ffi` came with pdfrx already; they are
  declared now, since `lib/annotated_pdf.dart` calls PDFium's annotation API directly, while pdfrx's
  own PDFium worker waits (`useNativeDocumentHandle`). No new package.

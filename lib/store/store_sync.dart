// The phone's half of the store (phone ADR 3 section 1, desktop ADR 8): it reads what the desktop
// sent, writes its own place, and merges its notes. Everything goes through a [SyncStore], which
// knows files and nothing else, so the same code could serve another service, and is tested
// against a store in memory that the desktop's own engine filled.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../library.dart';
import '../notes_store.dart';
import '../shared/download_plan.dart';
import '../shared/notes.dart';
import '../shared/notes_merge.dart';
import '../shared/sync.dart';
import '../shared/sync_memo.dart';
import '../shared/sync_store.dart';

/// Thrown when what the store holds is not what it should be: a PDF that is not the document's, or a
/// pack that lacks a sentence. The document is left unlisted rather than half written.
class StoreSyncException implements Exception {
  const StoreSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A document in the store, as its sealed manifest says.
class CloudDocument {
  const CloudDocument(this.manifest);

  final Manifest manifest;
}

class CloudListing {
  const CloudListing(this.documents, this.unreadable);

  final List<CloudDocument> documents;

  /// Documents whose manifest this key could not open.
  final int unreadable;
}

class DownloadProgress {
  const DownloadProgress(this.name, this.done, this.total);

  final String name;

  /// Pages finished, out of `total`.
  final int done;
  final int total;
}

class SyncSummary {
  const SyncSummary({
    required this.updated,
    required this.notesChanged,
    required this.unreadable,
    this.newInCloud = const {},
  });

  /// Documents on the phone that were downloaded again because the desktop prepared them again.
  final int updated;

  /// Documents whose marks or comments changed on the phone.
  final int notesChanged;

  /// Files from other devices that this key could not open.
  final int unreadable;

  /// Documents another device's journal reported that this phone does not hold: new, or prepared
  /// again, in the cloud. An incremental sync does not list the cloud, so this is how the library
  /// learns of them.
  final Set<String> newInCloud;
}

final _docId = RegExp(r'^[0-9a-f]{64}$');
final _stateFile = RegExp(r'^([0-9a-f]{32})\.json$');

class StoreSync {
  StoreSync(
    this.store,
    this.key,
    this.library,
    this.notes,
    this.device, {
    SyncMemo? memo,
    this.name = '',
    int Function()? now,
  }) : memo = memo ?? SyncMemo(),
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final SyncStore store;
  final Uint8List key;
  final Library library;
  final NotesStore notes;

  /// This phone's id, which names its place in the store.
  final String device;

  /// This phone's name as the journal shows it to the other devices.
  final String name;

  /// What the last sync left (changed in place; the caller keeps it between syncs). Without it a
  /// sync walks everything.
  final SyncMemo memo;
  final int Function() _now;

  Directory _dir(String docId) => Directory('${library.root.path}/$docId');

  /// A file from the store, opened with the key. Null when there is none; throws a [SealException]
  /// when this key cannot open it.
  Future<Uint8List?> _open(String path) async {
    final sealed = await store.get(path);
    return sealed == null ? null : unseal(key, path, sealed);
  }

  /// Every document in the store whose manifest this key opens.
  Future<CloudListing> documents() async {
    final documents = <CloudDocument>[];
    var unreadable = 0;
    for (final entry in await store.list('')) {
      if (!entry.folder || !_docId.hasMatch(entry.name)) continue;
      try {
        final bytes = await _open(RemotePath.manifest(entry.name));
        // No manifest means the desktop is still sending it: the manifest is written last.
        if (bytes == null) continue;
        final manifest = parseManifest(jsonDecode(utf8.decode(bytes)));
        if (manifest == null || manifest.docId != entry.name) {
          unreadable++;
          continue;
        }
        documents.add(CloudDocument(manifest));
      } on SealException {
        unreadable++;
      } on FormatException {
        unreadable++;
      }
    }
    documents.sort((a, b) => a.manifest.name.toLowerCase().compareTo(b.manifest.name.toLowerCase()));
    return CloudListing(documents, unreadable);
  }

  /// Brings a document onto the phone in the layout of the Wi-Fi sync, so that everything after the
  /// download is the same. Returns false when the phone already had this very preparation. The
  /// manifest is written last, so a folder with one is a whole document.
  Future<bool> download(CloudDocument remote, void Function(DownloadProgress) progress) async {
    final manifest = remote.manifest;
    final dir = _dir(manifest.docId);
    final local = await library.read(dir);
    if (isCurrent(manifest, local?.manifest)) return false;
    // Until the new manifest is written the folder is not a whole document.
    final held = File('${dir.path}/manifest.json');
    if (await held.exists()) await held.delete();
    await dir.create(recursive: true);

    // Its id is its hash, so a PDF already here is the same PDF.
    final pdf = File('${dir.path}/document.pdf');
    if (!await pdf.exists()) {
      final bytes = await _open(RemotePath.pdf(manifest.docId));
      if (bytes == null) throw StoreSyncException('${manifest.name} has no PDF in the store');
      if (sha256.convert(bytes).toString() != manifest.docId) {
        throw StoreSyncException('The PDF in the store is not the one ${manifest.name} is named for');
      }
      await pdf.writeAsBytes(bytes);
    }

    final pages = <PageIndex>[];
    for (var page = 1; page <= manifest.pages; page++) {
      progress(DownloadProgress(manifest.name, page - 1, manifest.pages));
      final bytes = await _open(RemotePath.page(manifest.docId, page));
      final index = bytes == null ? null : parsePageIndex(jsonDecode(utf8.decode(bytes)));
      if (bytes == null || index == null) {
        throw StoreSyncException('Page $page of ${manifest.name} is missing or not valid');
      }
      final pack = await _open(RemotePath.pack(manifest.docId, page));
      final files = pack == null ? null : unpackAudio(pack);
      if (files == null) {
        throw StoreSyncException('The audio of page $page of ${manifest.name} is missing or not valid');
      }
      final audio = Directory('${dir.path}/audio');
      await audio.create(recursive: true);
      final have = {for (final f in files) f.key};
      final missing = {for (final s in index.sentences) s.key}.where((k) => !have.contains(k));
      if (missing.isNotEmpty) {
        throw StoreSyncException(
          'The audio of page $page of ${manifest.name} lacks ${missing.length} sentences',
        );
      }
      for (final f in files) {
        final file = File('${audio.path}/${f.key}.opus');
        // A sentence that two pages share is in both packs; once is enough.
        if (!await file.exists()) await file.writeAsBytes(f.bytes);
      }
      await Directory('${dir.path}/pages').create(recursive: true);
      await File('${dir.path}/pages/$page.json').writeAsBytes(bytes);
      pages.add(index);
    }
    // Audio no page refers to any more, as after the desktop prepared the document with other voices.
    final audio = Directory('${dir.path}/audio');
    final onDisk = {
      for (final f in audio.listSync().whereType<File>())
        if (f.path.endsWith('.opus')) f.uri.pathSegments.last.replaceAll('.opus', ''),
    };
    for (final unused in audioToRemove(pages, onDisk)) {
      await File('${audio.path}/$unused.opus').delete();
    }
    progress(DownloadProgress(manifest.name, manifest.pages, manifest.pages));
    // Last: the manifest as the desktop sealed it.
    final manifestBytes = await _open(RemotePath.manifest(manifest.docId));
    await held.writeAsBytes(manifestBytes!);
    return true;
  }

  /// Sends this phone's place in a document when [push] says so and keeps the other devices' when
  /// [pull] does (desktop ADR 7 section 8). Each device writes only its own file, so nothing is
  /// merged. Returns how many files from other devices could not be read.
  Future<int> exchangeStates(String docId, {bool push = true, bool pull = true}) async {
    final dir = Directory('${_dir(docId).path}/state');
    final own = File('${dir.path}/$device.json');
    if (push && await own.exists()) {
      final path = RemotePath.state(docId, device);
      await store.put(path, await seal(key, path, await own.readAsBytes()));
    }
    if (!pull) return 0;
    var unreadable = 0;
    for (final entry in await store.list(RemotePath.states(docId))) {
      final match = _stateFile.firstMatch(entry.name);
      if (match == null || entry.folder || match.group(1) == device) {
        // Not a state file of another device: a name that is not one is not ours to read.
        if (match == null && !entry.folder) unreadable++;
        continue;
      }
      DeviceState? state;
      try {
        final bytes = await _open(RemotePath.state(docId, match.group(1)!));
        state = bytes == null ? null : parseDeviceState(jsonDecode(utf8.decode(bytes)));
      } on SealException {
        state = null;
      } on FormatException {
        state = null;
      }
      // A state belongs to the device whose name the file carries.
      if (state == null || state.device != match.group(1)) {
        unreadable++;
        continue;
      }
      await dir.create(recursive: true);
      await File('${dir.path}/${entry.name}').writeAsString(jsonEncode(state.toJson()));
    }
    return unreadable;
  }

  /// Exchanges a document's marks and comments: this phone's and the store's are merged per mark
  /// (desktop ADR 7 section 1), and whichever side lacks the result gets it. No logic runs in the
  /// store, so two devices that write at the same moment can lose one update; the next sync merges
  /// again, since the merge loses nothing that either side still holds.
  /// // shortcut: no revision check on the notes file, upgrade if a lost update is ever seen.
  Future<({bool changed, bool sent, String? hash, int unreadable})> exchangeNotes(String docId) async {
    final local = await notes.load(docId);
    final path = RemotePath.notes(docId);
    NotesFile? remote;
    final sealed = await store.get(path);
    if (sealed != null) {
      try {
        remote = parseNotes(jsonDecode(utf8.decode(await unseal(key, path, sealed))));
      } on SealException {
        remote = null;
      } on FormatException {
        remote = null;
      }
      // Another key, or a changed file: left as it is, and counted.
      if (remote == null) return (changed: false, sent: false, hash: null, unreadable: 1);
    }
    final hasLocal = local.annotations.isNotEmpty || local.notes.isNotEmpty || local.removed.isNotEmpty;
    final NotesFile? merged = hasLocal && remote != null
        ? mergeNotes(local, remote)
        : (hasLocal ? local : remote);
    if (merged == null) return (changed: false, sent: false, hash: null, unreadable: 0);
    final text = encodeNotes(merged);
    var changed = false;
    if (encodeNotes(local) != text) {
      await notes.save(docId, merged, fromSync: true);
      changed = true;
    }
    final sent = remote == null || encodeNotes(remote) != text;
    if (sent) await store.put(path, await seal(key, path, Uint8List.fromList(utf8.encode(text))));
    return (changed: changed, sent: sent, hash: sha256Of(text), unreadable: 0);
  }

  /// The journals of the other devices: one listing of `devices/`, and only a journal whose ETag moved
  /// is opened. [full] opens every journal and reports every document as changed.
  Future<_Poll> _poll(bool full) async {
    final changed = <String, List<JournalPart>>{};
    final opened = <String, SeenJournal>{};
    Journal? own;
    var unreadable = 0;
    for (final entry in await store.list(RemotePath.journals)) {
      final match = _stateFile.firstMatch(entry.name);
      if (match == null || entry.folder) continue;
      final id = match.group(1)!;
      // This phone's own journal is only read to repair it, in a full walk.
      if (id == device && !full) continue;
      final before = memo.seen[id];
      if (id != device && !full && entry.etag != null && before?.etag == entry.etag) continue;
      Journal? journal;
      try {
        final bytes = await _open(RemotePath.journal(id));
        journal = bytes == null ? null : parseJournal(jsonDecode(utf8.decode(bytes)));
      } on SealException {
        journal = null;
      } on FormatException {
        journal = null;
      }
      // A journal belongs to the device whose name the file carries.
      if (journal == null || journal.device != id) {
        unreadable++;
        continue;
      }
      if (id == device) {
        own = journal;
        continue;
      }
      opened[id] = SeenJournal(entry.etag ?? '', journal);
      changedParts(full ? null : before?.journal, journal).forEach((docId, parts) {
        changed[docId] = {...?changed[docId], ...parts}.toList();
      });
    }
    return _Poll(changed, opened, own, unreadable);
  }

  /// A sync of what is on the phone: a document the desktop prepared again is downloaded again, and
  /// each document's place and notes are exchanged. A document that is only in the store is not
  /// downloaded: that is the user's choice, on a phone that may be on mobile data.
  ///
  /// With a memo it asks the store one question, which journals changed, and touches only the
  /// documents and parts they name, plus whatever changed here. The first sync, one after the memo was
  /// lost and a [full] one walk everything, which also writes a lost journal again.
  Future<SyncSummary> sync(void Function(DownloadProgress) progress, {bool full = false}) async {
    // Nothing sent yet means nothing is known: walk everything once.
    final walk = full || memo.own.isEmpty;
    final poll = await _poll(walk);
    // A memo lost while the store kept this phone's journal starts from that journal.
    if (memo.own.isEmpty && poll.own != null) memo.own = {...poll.own!.docs};

    final listing = walk ? await documents() : null;
    final inCloud = <String>{
      if (listing != null)
        for (final doc in listing.documents) doc.manifest.docId
      else ...{
        // Those that were in the cloud at the last walk, and those other devices' journals name.
        ...memo.own.keys,
        for (final entry in memo.seen.values) ...entry.journal.docs.keys,
        for (final entry in poll.opened.values) ...entry.journal.docs.keys,
      },
    };
    final own = <String, JournalDoc>{};
    final nextSynced = <String, SyncedHashes>{};
    var dirty = false;
    var updated = 0;
    var notesChanged = 0;
    var unreadable = poll.unreadable + (listing?.unreadable ?? 0);
    final onPhone = <String>{};

    for (final local in await library.documents()) {
      final docId = local.manifest.docId;
      onPhone.add(docId);
      if (!inCloud.contains(docId)) continue;
      own[docId] = memo.own[docId] ?? const JournalDoc();
      final parts = poll.changed[docId] ?? const <JournalPart>[];
      var synced = memo.synced[docId] ?? const SyncedHashes();
      // Strictly later than before, since the readers compare for a difference.
      void stamp(JournalPart part) {
        own[docId] = own[docId]!.withPart(part, max(_now(), (memo.own[docId]?.at(part) ?? -1) + 1));
        dirty = true;
      }

      if (walk || parts.contains(JournalPart.manifest)) {
        final remote = listing == null
            ? await _remoteDocument(docId)
            : listing.documents.where((d) => d.manifest.docId == docId).firstOrNull;
        if (remote != null && await download(remote, progress)) updated++;
      }

      final stateHash = await _stateHash(docId);
      final stateChanged = stateHash != null && stateHash != synced.state;
      unreadable += await exchangeStates(
        docId,
        push: walk || stateChanged,
        pull: walk || parts.contains(JournalPart.state),
      );
      if (stateChanged) {
        stamp(JournalPart.state);
        synced = SyncedHashes(notes: synced.notes, state: stateHash);
      }

      final notesHash = await _notesHash(docId);
      if (walk || parts.contains(JournalPart.notes) || (notesHash != null && notesHash != synced.notes)) {
        final result = await exchangeNotes(docId);
        unreadable += result.unreadable;
        if (result.changed) notesChanged++;
        if (result.sent) stamp(JournalPart.notes);
        if (result.hash != null) synced = SyncedHashes(notes: result.hash, state: synced.state);
      }
      nextSynced[docId] = synced;
    }

    // Documents no longer on the phone leave the journal too.
    if (own.length != memo.own.length) dirty = true;
    // A journal the store lost, or that differs from ours, is written again by any full walk.
    if (walk) {
      final theirs = poll.own?.docs;
      final same =
          theirs != null && theirs.length == own.length && own.entries.every((e) => theirs[e.key] == e.value);
      if (theirs == null ? own.isNotEmpty : !same) dirty = true;
    }
    // Last, so that nobody is told of a part that is not in the store yet.
    if (dirty) {
      final journal = Journal(device: device, name: name, updated: _now(), docs: own);
      final path = RemotePath.journal(device);
      await store.put(
        path,
        await seal(key, path, Uint8List.fromList(utf8.encode(jsonEncode(journal.toJson())))),
      );
    }
    // Only now is the memo changed: a sync that failed above reads the same journals again.
    memo.own = own;
    memo.synced = nextSynced;
    memo.seen.addAll(poll.opened);
    return SyncSummary(
      updated: updated,
      notesChanged: notesChanged,
      unreadable: unreadable,
      newInCloud: {
        for (final docId in poll.changed.keys)
          if (poll.changed[docId]!.contains(JournalPart.manifest) && !onPhone.contains(docId)) docId,
      },
    );
  }

  /// The document as its manifest in the store says, or null when there is none.
  Future<CloudDocument?> _remoteDocument(String docId) async {
    final bytes = await _open(RemotePath.manifest(docId));
    final manifest = bytes == null ? null : parseManifest(jsonDecode(utf8.decode(bytes)));
    return manifest != null && manifest.docId == docId ? CloudDocument(manifest) : null;
  }

  /// The hash of this phone's own place in a document, or null when it has none.
  Future<String?> _stateHash(String docId) async {
    final file = File('${_dir(docId).path}/state/$device.json');
    return await file.exists() ? sha256Of(await file.readAsBytes()) : null;
  }

  /// The hash `exchangeNotes` would record for the notes here, or null when there are none.
  Future<String?> _notesHash(String docId) async {
    final local = await notes.load(docId);
    final hasLocal = local.annotations.isNotEmpty || local.notes.isNotEmpty || local.removed.isNotEmpty;
    return hasLocal ? sha256Of(encodeNotes(local)) : null;
  }
}

class _Poll {
  const _Poll(this.changed, this.opened, this.own, this.unreadable);

  final Map<String, List<JournalPart>> changed;
  final Map<String, SeenJournal> opened;
  final Journal? own;
  final int unreadable;
}

String sha256Of(Object data) =>
    sha256.convert(data is String ? utf8.encode(data) : data as List<int>).toString();

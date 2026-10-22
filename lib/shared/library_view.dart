// The phone's one list of documents (desktop ADR 10 section 4): what is on this phone, what is only in
// the cloud, and what is out of date, each with its state. Pure, so the states and filters are tested
// without a screen.
import 'download_plan.dart';
import 'sync.dart';

/// onPhone: here and up to date. updateAvailable: here, and the desktop prepared it again.
/// inCloud: not here. downloading: a download is running, for either of the last two.
enum DocState { onPhone, updateAvailable, inCloud, downloading }

enum LibraryFilter { all, onPhone, cloudOnly }

class LibraryEntry {
  const LibraryEntry({required this.manifest, required this.state, this.local, this.progress});

  /// The newest manifest known: the cloud's if it has one, else the phone's.
  final Manifest manifest;

  /// The phone's copy, or null when the document is only in the cloud.
  final Manifest? local;
  final DocState state;

  /// How far a running download is, 0 to 1, or null when not known (or not downloading).
  final double? progress;

  bool get onThisPhone => local != null;
}

/// Every document the phone knows. [downloading] maps a document's id to its progress, null if
/// the download has not said yet.
List<LibraryEntry> libraryEntries({
  required List<Manifest> local,
  required List<Manifest> cloud,
  Map<String, double?> downloading = const {},
}) {
  final here = {for (final m in local) m.docId: m};
  final there = {for (final m in cloud) m.docId: m};
  final entries = [
    for (final docId in {...here.keys, ...there.keys})
      LibraryEntry(
        manifest: there[docId] ?? here[docId]!,
        local: here[docId],
        progress: downloading[docId],
        state: switch ((downloading.containsKey(docId), here[docId], there[docId])) {
          (true, _, _) => DocState.downloading,
          (_, null, _) => DocState.inCloud,
          (_, final mine?, final theirs?) when !isCurrent(theirs, mine) => DocState.updateAvailable,
          _ => DocState.onPhone,
        },
      ),
  ]..sort((a, b) => a.manifest.name.toLowerCase().compareTo(b.manifest.name.toLowerCase()));
  return entries;
}

List<LibraryEntry> filterEntries(List<LibraryEntry> entries, LibraryFilter filter) => switch (filter) {
  LibraryFilter.all => entries,
  LibraryFilter.onPhone => [
    for (final e in entries)
      if (e.onThisPhone) e,
  ],
  LibraryFilter.cloudOnly => [
    for (final e in entries)
      if (!e.onThisPhone) e,
  ],
};

/// What the documents on this phone take up.
int spaceUsed(List<LibraryEntry> entries) => entries.fold(0, (sum, e) => sum + (e.local?.bytes ?? 0));

/// 1.2 GB, 340 MB, 12 KB: what a person reads at a glance.
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  if (bytes >= 1024 * 1024) return '${(bytes / 1024 / 1024).round()} MB';
  return '${(bytes / 1024).ceil()} KB';
}

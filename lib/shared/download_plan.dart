// What a sync fetches from the desktop (PLAN step 5.4): only what the phone lacks. The PDF never
// changes under its id, which is its hash, so the manifest's update time tells whether the pages
// and audio changed.
import 'sync.dart';

/// Whether the phone's copy is the desktop's current one, so nothing needs fetching.
bool isCurrent(Manifest remote, Manifest? local) =>
    local != null && local.docId == remote.docId && local.updated == remote.updated;

Set<String> _keys(List<PageIndex> pages) => {
  for (final page in pages)
    for (final s in page.sentences) s.key,
};

/// The audio the pages need and the phone does not have, each once, in page order.
List<String> audioToFetch(List<PageIndex> pages, Set<String> have) =>
    _keys(pages).where((key) => !have.contains(key)).toList();

/// The audio no page refers to any more.
List<String> audioToRemove(List<PageIndex> pages, Set<String> have) {
  final used = _keys(pages);
  return have.where((key) => !used.contains(key)).toList();
}

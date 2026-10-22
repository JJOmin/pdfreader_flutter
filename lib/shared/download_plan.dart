// What a sync fetches from the desktop (PLAN step 5.4): only what the phone lacks. The PDF never
// changes under its id, which is its hash, so the manifest's update time tells whether the pages
// and audio changed.
import 'sync.dart';

/// Whether the phone's copy is the desktop's current one, so nothing needs fetching.
bool isCurrent(Manifest remote, Manifest? local) =>
    local != null && local.docId == remote.docId && local.updated == remote.updated;

/// The voiced pages the phone has to fetch so that `have` matches `want`: those it lacks, or all of
/// them when its audio was made with other voices (desktop ADR 11).
List<int> pagesToFetch(Manifest? have, Manifest want) {
  if (have == null || have.voices != want.voices) return [...want.voiced];
  final held = have.voiced.toSet();
  return [
    for (final page in want.voiced)
      if (!held.contains(page)) page,
  ];
}

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

// The two short lists at the top of the Home tab (PLAN 9.2). Pure, so the order is tested without a screen.

/// The documents read last, newest first. [lastRead] maps a document's id to when its place was saved.
List<String> continueReading(Map<String, num> lastRead, {int limit = 5}) =>
    (lastRead.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(limit)
        .map((e) => e.key)
        .toList();

/// Downloaded and never opened, newest download first. [downloaded] maps an id to when it arrived.
List<String> newOnPhone(Map<String, num> downloaded, Set<String> opened, {int limit = 5}) => continueReading({
  for (final e in downloaded.entries)
    if (!opened.contains(e.key)) e.key: e.value,
}, limit: limit);

/// A document from the library is remembered as `library:<docId>`; one opened from the picker by its URI.
String? docIdOfPlace(String key) => key.startsWith('library:') ? key.substring('library:'.length) : null;

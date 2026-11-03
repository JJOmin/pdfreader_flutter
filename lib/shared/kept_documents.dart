// PDFs opened from Files or another app (PLAN 18.10). The app keeps a copy in its own storage, so Home
// can open them again at their place; only the ones read last are kept.

/// How many opened PDFs are kept; the one not opened for longest goes first.
const keptLimit = 10;

final _id = RegExp(r'^[0-9a-f]{64}$');

class KeptDocument {
  const KeptDocument({required this.id, required this.name, required this.opened});

  /// The SHA-256 of the PDF's bytes, which also names its copy.
  final String id;
  final String name;

  /// When it was last opened, in milliseconds.
  final num opened;
}

/// The list after a PDF was opened at `now`: newest first, each PDF once, at most `limit`. `dropped`
/// names the ones that fell out, whose copies can go.
({List<KeptDocument> kept, List<String> dropped}) keepOpened(
  List<KeptDocument> list,
  String id,
  String name,
  num now, {
  int limit = keptLimit,
}) {
  final all = [
    KeptDocument(id: id, name: name, opened: now),
    for (final d in list)
      if (d.id != id) d,
  ];
  return (kept: all.take(limit).toList(), dropped: [for (final d in all.skip(limit)) d.id].reversed.toList());
}

Object keptToJson(List<KeptDocument> list) => [
  for (final d in list) {'id': d.id, 'name': d.name, 'opened': d.opened},
];

/// The list as read from disk. An id becomes a file name, so one that is not a hash is left out.
List<KeptDocument> parseKept(Object? json) => [
  if (json is List<Object?>)
    for (final item in json)
      if (item case {'id': final String id, 'name': final String name, 'opened': final num opened}
          when _id.hasMatch(id))
        KeptDocument(id: id, name: name, opened: opened),
];

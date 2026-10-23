// Liked documents and the user's folders (PLAN 9.3). A document can be in many folders, so a folder
// works as a tag. Kept on this phone only.
// shortcut: not synced; when the desktop gets folders, they join the library like notes.

class Folder {
  const Folder({
    required this.id,
    required this.name,
    required this.color,
    this.notes = '',
    this.docs = const [],
  });

  final String id;
  final String name;

  /// ARGB, as Flutter's `Color.toARGB32` gives it.
  final int color;
  final String notes;

  /// The documents' ids, in the order they were added.
  final List<String> docs;

  Folder copyWith({String? name, int? color, String? notes, List<String>? docs}) => Folder(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    notes: notes ?? this.notes,
    docs: docs ?? this.docs,
  );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'color': color, 'notes': notes, 'docs': docs};
}

class Favourites {
  const Favourites({this.liked = const {}, this.folders = const []});

  final Set<String> liked;
  final List<Folder> folders;

  bool isLiked(String docId) => liked.contains(docId);

  Favourites toggleLike(String docId) =>
      Favourites(liked: isLiked(docId) ? ({...liked}..remove(docId)) : {...liked, docId}, folders: folders);

  /// Adds the folder, or replaces the one with its id.
  Favourites putFolder(Folder folder) => Favourites(
    liked: liked,
    folders: folders.any((f) => f.id == folder.id)
        ? [for (final f in folders) f.id == folder.id ? folder : f]
        : [...folders, folder],
  );

  Favourites removeFolder(String id) => Favourites(
    liked: liked,
    folders: [
      for (final f in folders)
        if (f.id != id) f,
    ],
  );

  List<Folder> foldersOf(String docId) => [
    for (final f in folders)
      if (f.docs.contains(docId)) f,
  ];

  /// Puts the document in exactly the folders named.
  Favourites setFolders(String docId, Set<String> folderIds) => Favourites(
    liked: liked,
    folders: [
      for (final f in folders)
        switch ((f.docs.contains(docId), folderIds.contains(f.id))) {
          (false, true) => f.copyWith(docs: [...f.docs, docId]),
          (true, false) => f.copyWith(
            docs: [
              for (final d in f.docs)
                if (d != docId) d,
            ],
          ),
          _ => f,
        },
    ],
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'liked': liked.toList(),
    'folders': [for (final f in folders) f.toJson()],
  };
}

/// A missing or broken file is read as no favourites; a folder without an id or a name is left out.
Favourites parseFavourites(Object? json) {
  if (json is! Map) return const Favourites();
  final liked = json['liked'];
  final folders = json['folders'];
  return Favourites(
    liked: {if (liked is List) ...liked.whereType<String>()},
    folders: [
      if (folders is List)
        for (final f in folders.whereType<Map<Object?, Object?>>())
          if ((f['id'], f['name']) case (final String id, final String name))
            Folder(
              id: id,
              name: name,
              color: f['color'] is int ? f['color']! as int : 0xFF9E9E9E,
              notes: f['notes'] is String ? f['notes']! as String : '',
              docs: [if (f['docs'] case final List<Object?> docs) ...docs.whereType<String>()],
            ),
    ],
  );
}

/// What the Favourites tab lists. With no search: the liked documents and those in a folder. A search
/// looks at every document, by its title and its folders' names. [folder] or [likedOnly] narrow both.
List<T> searchDocuments<T>(
  List<T> docs,
  String Function(T) docId,
  String Function(T) name,
  Favourites favourites, {
  String query = '',
  String? folder,
  bool likedOnly = false,
}) {
  final q = query.trim().toLowerCase();
  final inFolder = folder == null
      ? null
      : favourites.folders.where((f) => f.id == folder).firstOrNull?.docs.toSet();
  bool shown(T d) {
    final id = docId(d);
    if (inFolder != null && !inFolder.contains(id)) return false;
    if (likedOnly && !favourites.isLiked(id)) return false;
    final folders = favourites.foldersOf(id);
    if (q.isEmpty) return favourites.isLiked(id) || folders.isNotEmpty;
    return name(d).toLowerCase().contains(q) || folders.any((f) => f.name.toLowerCase().contains(q));
  }

  return docs.where(shown).toList();
}

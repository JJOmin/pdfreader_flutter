// The Favourites tab (PLAN 9.3): a search over titles and folder names, chips for Liked and each
// folder, the folders, and the documents they hold.
import 'package:flutter/material.dart';

import 'favourites_store.dart';
import 'library_list.dart';
import 'shared/favourites.dart';
import 'shared/library_view.dart';
import 'shared/notes.dart' show newId;

/// The colours a folder can take.
const folderColors = [
  0xFF3F51B5, // indigo
  0xFF2196F3, // blue
  0xFF009688, // teal
  0xFF4CAF50, // green
  0xFFFFC107, // amber
  0xFFFF5722, // deep orange
  0xFFE91E63, // pink
  0xFF9C27B0, // purple
];

/// Shown in the filter while the liked documents are chosen.
const _liked = '';

class FavouritesTab extends StatefulWidget {
  const FavouritesTab({
    super.key,
    required this.favourites,
    required this.entries,
    required this.onOpen,
    required this.onDownload,
    required this.onRemove,
    required this.onOffer,
  });

  final FavouritesStore favourites;

  /// Every document the phone knows, as on Home.
  final List<LibraryEntry> entries;
  final void Function(LibraryEntry) onOpen;
  final void Function(LibraryEntry) onDownload;
  final void Function(LibraryEntry) onRemove;
  final void Function(LibraryEntry) onOffer;

  @override
  State<FavouritesTab> createState() => _FavouritesTabState();
}

class _FavouritesTabState extends State<FavouritesTab> {
  final _search = TextEditingController();

  /// Null: everything; [_liked]: the liked documents; else a folder's id.
  String? _filter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: SearchBar(
        key: const Key('favourites-search'),
        controller: _search,
        hintText: 'Search titles and folders',
        leading: const Icon(Icons.search),
        trailing: [
          if (_search.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear',
              onPressed: () => setState(_search.clear),
            ),
        ],
        elevation: const WidgetStatePropertyAll(0),
        onChanged: (_) => setState(() {}),
      ),
    ),
    body: ValueListenableBuilder(
      valueListenable: widget.favourites,
      builder: (context, favourites, _) {
        final folder = favourites.folders.where((f) => f.id == _filter).firstOrNull;
        // A folder deleted while chosen leaves the filter.
        final filter = _filter == _liked || folder != null ? _filter : null;
        final found = searchDocuments(
          widget.entries,
          (e) => e.manifest.docId,
          (e) => e.manifest.name,
          favourites,
          query: _search.text,
          folder: folder?.id,
          likedOnly: filter == _liked,
        );
        final browsing = filter == null && _search.text.trim().isEmpty;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  key: const Key('filter-liked'),
                  avatar: const Icon(Icons.favorite, size: 18),
                  label: const Text('Liked'),
                  selected: filter == _liked,
                  onSelected: (on) => setState(() => _filter = on ? _liked : null),
                ),
                for (final f in favourites.folders)
                  FilterChip(
                    key: Key('filter-folder-${f.name}'),
                    avatar: CircleAvatar(backgroundColor: Color(f.color), radius: 8),
                    label: Text(f.name),
                    selected: filter == f.id,
                    onSelected: (on) => setState(() => _filter = on ? f.id : null),
                  ),
              ],
            ),
            if (folder != null) _folderCard(folder),
            if (browsing && favourites.folders.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Folders', style: Theme.of(context).textTheme.titleSmall),
              for (final f in favourites.folders)
                ListTile(
                  key: Key('folder-${f.name}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.folder, color: Color(f.color)),
                  title: Text(f.name),
                  subtitle: Text(
                    [
                      f.docs.length == 1 ? '1 document' : '${f.docs.length} documents',
                      if (f.notes.isNotEmpty) f.notes,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => setState(() => _filter = f.id),
                ),
              const SizedBox(height: 8),
              Text('Documents', style: Theme.of(context).textTheme.titleSmall),
            ],
            if (found.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  browsing
                      ? 'Like a document or put it in a folder from its menu, and it appears here.'
                      : 'Nothing found.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              LibraryList(
                entries: found,
                showSpace: false,
                onOpen: widget.onOpen,
                onDownload: widget.onDownload,
                onRemove: widget.onRemove,
                onOffer: widget.onOffer,
                isLiked: (e) => favourites.isLiked(e.manifest.docId),
                onLike: (e) => widget.favourites.change((f) => f.toggleLike(e.manifest.docId)),
                onFolders: (e) => chooseFolders(context, widget.favourites, e.manifest.docId),
              ),
          ],
        );
      },
    ),
  );

  Widget _folderCard(Folder folder) => Card(
    margin: const EdgeInsets.only(top: 8),
    child: ListTile(
      leading: Icon(Icons.folder, color: Color(folder.color)),
      title: Text(folder.name),
      subtitle: folder.notes.isEmpty ? null : Text(folder.notes),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('edit-folder'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit folder',
            onPressed: () => editFolder(context, widget.favourites, folder),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete folder',
            onPressed: () => _delete(folder),
          ),
        ],
      ),
    ),
  );

  Future<void> _delete(Folder folder) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete the folder ${folder.name}?'),
        content: const Text('Its documents stay on the phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (sure != true) return;
    setState(() => _filter = null);
    await widget.favourites.change((f) => f.removeFolder(folder.id));
  }
}

/// Makes a folder, or changes [folder]: its name, colour and notes. Returns the folder saved.
Future<Folder?> editFolder(BuildContext context, FavouritesStore store, [Folder? folder]) async {
  final saved = await showDialog<Folder>(context: context, builder: (_) => _FolderDialog(folder));
  if (saved != null) await store.change((f) => f.putFolder(saved));
  return saved;
}

/// Owns its text fields, which the dialog still shows while it closes.
class _FolderDialog extends StatefulWidget {
  const _FolderDialog(this.folder);

  final Folder? folder;

  @override
  State<_FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends State<_FolderDialog> {
  late final _name = TextEditingController(text: widget.folder?.name);
  late final _notes = TextEditingController(text: widget.folder?.notes);
  late var _color = widget.folder?.color ?? folderColors.first;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.folder == null ? 'New folder' : 'Edit folder'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('folder-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in folderColors)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _color = c),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(c),
                    child: c == _color ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('folder-notes'),
            controller: _notes,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const Key('save-folder'),
        onPressed: _name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(
                context,
                (widget.folder ?? Folder(id: newId(), name: '', color: _color)).copyWith(
                  name: _name.text.trim(),
                  color: _color,
                  notes: _notes.text.trim(),
                ),
              ),
        child: const Text('Save'),
      ),
    ],
  );
}

/// The folders a document is in, each a tick; a new folder can be made here and gets the document.
Future<void> chooseFolders(BuildContext context, FavouritesStore store, String docId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ValueListenableBuilder(
        valueListenable: store,
        builder: (context, favourites, _) {
          final inside = {for (final f in favourites.foldersOf(docId)) f.id};
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('Folders')),
                for (final f in favourites.folders)
                  CheckboxListTile(
                    key: Key('in-folder-${f.name}'),
                    secondary: Icon(Icons.folder, color: Color(f.color)),
                    title: Text(f.name),
                    value: inside.contains(f.id),
                    onChanged: (on) => store.change(
                      (v) =>
                          v.setFolders(docId, on == true ? {...inside, f.id} : ({...inside}..remove(f.id))),
                    ),
                  ),
                ListTile(
                  key: const Key('new-folder-here'),
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: const Text('New folder'),
                  onTap: () async {
                    final made = await editFolder(context, store);
                    if (made != null) await store.change((v) => v.setFolders(docId, {...inside, made.id}));
                  },
                ),
              ],
            ),
          );
        },
      ),
    );

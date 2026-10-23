// The home screen's one list of documents (desktop ADR 10 section 4): each with its state, filter chips,
// the space used, and a menu per document. It only shows; the callbacks do the work.
import 'package:flutter/material.dart';

import 'shared/library_view.dart';

class LibraryList extends StatefulWidget {
  const LibraryList({
    super.key,
    required this.entries,
    required this.onOpen,
    required this.onDownload,
    required this.onRemove,
    required this.onOffer,
    this.isLiked,
    this.onLike,
    this.onFolders,
    this.showSpace = true,
  });

  final List<LibraryEntry> entries;
  final void Function(LibraryEntry) onOpen;
  final void Function(LibraryEntry) onDownload;
  final void Function(LibraryEntry) onRemove;

  /// A tap on an offered document: the question "Accept / Decline".
  final void Function(LibraryEntry) onOffer;

  /// Favourites (PLAN 9.3): the heart and the folders, in each document's menu.
  final bool Function(LibraryEntry)? isLiked;
  final void Function(LibraryEntry)? onLike;
  final void Function(LibraryEntry)? onFolders;

  /// The space used and the filter chips, which the Favourites tab leaves out.
  final bool showSpace;

  @override
  State<LibraryList> createState() => _LibraryListState();
}

class _LibraryListState extends State<LibraryList> {
  var _filter = LibraryFilter.all;

  static const _labels = {
    LibraryFilter.all: 'All',
    LibraryFilter.onPhone: 'On this phone',
    LibraryFilter.cloudOnly: 'Cloud only',
  };

  String _subtitle(LibraryEntry e) {
    final m = e.manifest;
    // The computer adds the audio page by page (desktop ADR 11).
    final audio = m.voiced.length == m.pages || e.state == DocState.offered
        ? ''
        : m.voiced.isEmpty
        ? ' · no audio yet'
        : ' · audio ${m.voiced.length} of ${m.pages} pages';
    final size = '${formatBytes(m.bytes)}$audio';
    return switch (e.state) {
      DocState.onPhone => 'On this phone · $size',
      DocState.updateAvailable => 'Update available · $size',
      DocState.inCloud => 'In the cloud · $size',
      DocState.downloading =>
        e.progress == null ? 'Downloading…' : 'Downloading ${(e.progress! * 100).round()} %',
      DocState.offered => 'Offered by ${e.offer!.from} · $size',
    };
  }

  Widget _leading(LibraryEntry e) => switch (e.state) {
    DocState.onPhone => const Icon(Icons.check_circle_outline),
    DocState.updateAvailable => const Icon(Icons.update),
    DocState.inCloud => const Icon(Icons.cloud_outlined),
    DocState.offered => const Icon(Icons.move_to_inbox_outlined),
    DocState.downloading => SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(value: e.progress, strokeWidth: 3),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final shown = filterEntries(widget.entries, _filter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showSpace) ...[
          Text(
            '${formatBytes(spaceUsed(widget.entries))} on this phone',
            key: const Key('space-used'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final filter in LibraryFilter.values)
                ChoiceChip(
                  key: Key('filter-${filter.name}'),
                  label: Text(_labels[filter]!),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
        ],
        for (final e in widget.showSpace ? shown : widget.entries)
          ListTile(
            key: Key('doc-${e.manifest.docId}'),
            leading: _leading(e),
            title: Text(e.manifest.name),
            subtitle: e.state == DocState.downloading
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_subtitle(e)),
                      LinearProgressIndicator(value: e.progress),
                    ],
                  )
                : Text(_subtitle(e)),
            onTap: e.state == DocState.downloading
                ? null
                : () => e.state == DocState.offered
                      ? widget.onOffer(e)
                      : e.onThisPhone
                      ? widget.onOpen(e)
                      : widget.onDownload(e),
            trailing: e.state == DocState.downloading || e.state == DocState.offered
                ? null
                : PopupMenuButton<String>(
                    key: Key('menu-${e.manifest.docId}'),
                    onSelected: (choice) => switch (choice) {
                      'open' => widget.onOpen(e),
                      'download' => widget.onDownload(e),
                      'like' => widget.onLike!(e),
                      'folders' => widget.onFolders!(e),
                      _ => widget.onRemove(e),
                    },
                    itemBuilder: (context) => [
                      if (e.onThisPhone) const PopupMenuItem(value: 'open', child: Text('Open')),
                      if (!e.onThisPhone)
                        const PopupMenuItem(value: 'download', child: Text('Download'))
                      else if (e.state == DocState.updateAvailable)
                        const PopupMenuItem(value: 'download', child: Text('Download update')),
                      if (widget.onLike != null)
                        PopupMenuItem(
                          value: 'like',
                          child: Text(widget.isLiked?.call(e) ?? false ? 'Unlike' : 'Like'),
                        ),
                      if (widget.onFolders != null)
                        const PopupMenuItem(value: 'folders', child: Text('Folders…')),
                      if (e.onThisPhone)
                        const PopupMenuItem(value: 'remove', child: Text('Remove from this phone')),
                    ],
                  ),
          ),
      ],
    );
  }
}

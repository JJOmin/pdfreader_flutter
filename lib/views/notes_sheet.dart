import 'package:flutter/material.dart';

import '../shared/notes.dart';
import 'text_view.dart';

/// What the sheet reports back; the reader page owns the notes and saves them.
class NotesActions {
  const NotesActions({
    required this.onNotes,
    required this.onComment,
    required this.onDelete,
    required this.onJump,
  });

  final ValueChanged<String> onNotes;
  final void Function(String id, String comment) onComment;
  final ValueChanged<String> onDelete;

  /// Closes the sheet and shows the mark in the document.
  final ValueChanged<Annotation> onJump;
}

const _kindLabels = {
  MarkKind.highlight: 'Highlight',
  MarkKind.underline: 'Underline',
  MarkKind.strike: 'Strike',
};

/// One mark: its page and quote, an editable comment, and Delete.
class MarkCard extends StatefulWidget {
  const MarkCard({super.key, required this.mark, required this.found, required this.actions, this.onDeleted});

  final Annotation mark;

  /// False when the mark's text is no longer on its page, so it cannot be shown there.
  final bool found;
  final NotesActions actions;
  final VoidCallback? onDeleted;

  @override
  State<MarkCard> createState() => _MarkCardState();
}

class _MarkCardState extends State<MarkCard> {
  late final _comment = TextEditingController(text: widget.mark.comment);

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mark = widget.mark;
    final quote = mark.quote.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: Key('mark-${mark.id}'),
              onTap: widget.found ? () => widget.actions.onJump(mark) : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 44,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: markLine[mark.color],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Page ${mark.page} · ${_kindLabels[mark.kind]}${widget.found ? '' : ' · not found on its page'}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Text(quote, maxLines: 3, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            TextField(
              key: Key('comment-${mark.id}'),
              controller: _comment,
              minLines: 1,
              maxLines: 5,
              decoration: const InputDecoration(hintText: 'Comment', isDense: true),
              onChanged: (text) => widget.actions.onComment(mark.id, text),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
                onPressed: () {
                  widget.actions.onDelete(mark.id);
                  widget.onDeleted?.call();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The general notes and every mark, in reading order.
class NotesSheet extends StatefulWidget {
  const NotesSheet({
    super.key,
    required this.notes,
    required this.marks,
    required this.found,
    required this.actions,
  });

  final String notes;
  final List<Annotation> marks;

  /// The ids of the marks that are on their pages.
  final Set<String> found;
  final NotesActions actions;

  @override
  State<NotesSheet> createState() => _NotesSheetState();
}

class _NotesSheetState extends State<NotesSheet> {
  late final _notes = TextEditingController(text: widget.notes);
  late final _marks = sortAnnotations(widget.marks);

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.75,
    minChildSize: 0.4,
    maxChildSize: 0.95,
    builder: (context, scroll) => ListView(
      controller: scroll,
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      children: [
        Text('Notes', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          key: const Key('general-notes'),
          controller: _notes,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'General notes on this document',
            border: OutlineInputBorder(),
          ),
          onChanged: widget.actions.onNotes,
        ),
        const SizedBox(height: 16),
        Text('Marks', style: Theme.of(context).textTheme.titleMedium),
        if (_marks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Select text and choose a colour to mark it.'),
          ),
        for (final mark in _marks)
          MarkCard(
            key: ValueKey(mark.id),
            mark: mark,
            found: widget.found.contains(mark.id),
            actions: widget.actions,
            onDeleted: () => setState(() => _marks.removeWhere((m) => m.id == mark.id)),
          ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';

import '../shared/notes.dart';
import 'text_view.dart';

/// What the sheet reports back; the reader page owns the notes and saves them.
class NotesActions {
  const NotesActions({
    required this.onNotes,
    required this.onComment,
    required this.onStyle,
    required this.onDelete,
    required this.onJump,
  });

  final ValueChanged<String> onNotes;
  final void Function(String id, String comment) onComment;

  /// A mark's kind or colour was changed on its card.
  final void Function(String id, MarkKind kind, HighlightColor color) onStyle;
  final ValueChanged<String> onDelete;

  /// Closes the sheet and shows the mark in the document.
  final ValueChanged<Annotation> onJump;
}

const _kindLabels = {
  MarkKind.highlight: 'Highlight',
  MarkKind.underline: 'Underline',
  MarkKind.strike: 'Strike',
};

const _kindIcons = {
  MarkKind.highlight: Icons.format_color_fill,
  MarkKind.underline: Icons.format_underlined,
  MarkKind.strike: Icons.format_strikethrough,
};

/// One mark: its page and quote and its comment. The pencil opens it for changes: the comment, the
/// kind and the colour of the mark, and Delete. Closed, the card only shows.
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
  late var _kind = widget.mark.kind;
  late var _color = widget.mark.color;
  bool _editing = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _restyle({MarkKind? kind, HighlightColor? color}) {
    setState(() {
      _kind = kind ?? _kind;
      _color = color ?? _color;
    });
    widget.actions.onStyle(widget.mark.id, _kind, _color);
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
                    height: 48,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: markLine[_color],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Page ${mark.page} · ${_kindLabels[_kind]}${widget.found ? '' : ' · not found on its page'}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Text(quote, maxLines: 3, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    key: Key('edit-${mark.id}'),
                    icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
                    tooltip: _editing ? 'Done' : 'Edit the comment and the mark',
                    onPressed: () => setState(() => _editing = !_editing),
                  ),
                ],
              ),
            ),
            TextField(
              key: Key('comment-${mark.id}'),
              controller: _comment,
              // Closed, the comment can be read and copied but not changed.
              readOnly: !_editing,
              minLines: 1,
              maxLines: 5,
              decoration: InputDecoration(hintText: _editing ? 'Comment' : 'No comment'),
              onChanged: (text) => widget.actions.onComment(mark.id, text),
            ),
            if (_editing) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final kind in MarkKind.values)
                    IconButton.outlined(
                      key: Key('kind-${kind.name}-${mark.id}'),
                      isSelected: _kind == kind,
                      icon: Icon(_kindIcons[kind]),
                      tooltip: _kindLabels[kind],
                      onPressed: () => _restyle(kind: kind),
                    ),
                  for (final color in HighlightColor.values)
                    InkResponse(
                      key: Key('color-${color.name}-${mark.id}'),
                      onTap: () => _restyle(color: color),
                      // The circle is 32 dp; the part that takes a touch is 48, as Android asks.
                      child: Semantics(
                        label: color.name,
                        button: true,
                        selected: _color == color,
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          color: Colors.transparent,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: markLine[color],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.onSurface,
                                width: _color == color ? 3 : 0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
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

// A comment made quickly (PLAN 11): typed, or spoken into the on-device recogniser (ADR 6). What is
// heard lands in the text field as a draft the user can correct before saving, so a misheard word
// costs a tap, not a comment.
import 'package:flutter/material.dart';

import '../dictation.dart';

/// What the sheet gives back: the comment, and whether any of it was spoken, which marks it with the
/// microphone icon.
typedef QuickComment = ({String text, bool dictated});

class QuickCommentSheet extends StatefulWidget {
  const QuickCommentSheet({super.key, required this.quote, this.dictation, this.listenAtOnce = false});

  /// The passage the comment is for.
  final String quote;

  /// Null where the phone cannot recognise speech offline: the microphone is then not shown.
  final Dictation? dictation;
  final bool listenAtOnce;

  @override
  State<QuickCommentSheet> createState() => _QuickCommentSheetState();
}

class _QuickCommentSheetState extends State<QuickCommentSheet> {
  final _text = TextEditingController();
  bool _listening = false;
  bool _dictated = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    if (widget.listenAtOnce) WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  @override
  void dispose() {
    if (_listening) widget.dictation?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _put(String base, String heard) {
    final text = base.isEmpty ? heard : '$base $heard';
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _listen() async {
    final dictation = widget.dictation;
    if (dictation == null || _listening) return;
    final base = _text.text.trimRight();
    setState(() {
      _listening = true;
      _problem = null;
    });
    final heard = await dictation.listen(
      onPartial: (partial) {
        if (mounted) _put(base, partial);
      },
    );
    if (!mounted) return;
    setState(() {
      _listening = false;
      if (heard.text != null) {
        _put(base, heard.text!);
        _dictated = true;
      }
      _problem = heard.error ?? (heard.text == null && _text.text.trim() == base ? 'Nothing heard' : null);
    });
  }

  /// Ends listening early; what was said is still written out, by the `listen` that is waiting.
  Future<void> _stop() async => widget.dictation?.stop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quote = widget.quote.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Comment', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            quote,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('quick-comment'),
            controller: _text,
            autofocus: !widget.listenAtOnce && widget.dictation == null,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: _listening ? 'Listening…' : 'Your thought',
              border: const OutlineInputBorder(),
            ),
          ),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _problem!,
                key: const Key('dictation-problem'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          if (widget.dictation != null)
            Row(
              children: [
                IconButton.filledTonal(
                  key: const Key('dictate'),
                  iconSize: 28,
                  icon: Icon(_listening ? Icons.stop : Icons.mic),
                  tooltip: _listening ? 'Done speaking' : 'Speak the comment',
                  onPressed: _listening ? _stop : _listen,
                ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const Key('save-comment'),
                  onPressed: _listening
                      ? null
                      : () =>
                            Navigator.of(context)
                                .pop<QuickComment>((text: _text.text.trim(), dictated: _dictated)),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

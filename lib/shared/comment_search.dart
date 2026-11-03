// The search in the notes sheet (PLAN 18.8): it looks at the comments only, as the reader's own search
// looks at the document's text.
import 'notes.dart';

final _space = RegExp(r'\s+', unicode: true);

/// The marks whose comment holds every word of `query`, in any order and any case; every mark when
/// the query is empty.
List<Annotation> searchComments(List<Annotation> marks, String query) {
  final words = query.toLowerCase().split(_space).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return marks;
  return [
    for (final m in marks)
      if (m.comment.toLowerCase() case final comment when words.every(comment.contains)) m,
  ];
}

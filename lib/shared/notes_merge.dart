// Port of the desktop's src/shared/notes-merge.ts. Notes are merged per mark (desktop ADR 7 section
// 1, decided by the owner on 2026-10-21). Every mark carries the time it was last changed; a mark
// that was deleted is kept as a removal, so that the other device does not bring it back; the
// general notes carry their own time. A file written before these fields has none, and counts as
// the oldest.
import 'notes.dart';

num _stamp(Annotation a) => a.updated ?? 0;

/// `next`, a save of the notes, with its changes stamped by comparing it with `previous`, what was
/// stored before: a mark that is new or changed gets `now`, a mark that is gone becomes a removal,
/// and the general notes get `now` if their text changed.
NotesFile stampChanges(NotesFile? previous, NotesFile next, num now) {
  final before = {for (final a in previous?.annotations ?? const <Annotation>[]) a.id: a};
  final annotations = [
    for (final a in next.annotations)
      switch (before[a.id]) {
        final old? when encodeMark(old) == encodeMark(a) => _withTime(a, old.updated ?? a.updated),
        _ => _withTime(a, now),
      },
  ];
  final present = {for (final a in next.annotations) a.id};
  final removed = <String, num>{};
  for (final r in [...?previous?.removed, ...next.removed]) {
    final held = removed[r.id];
    removed[r.id] = held == null || r.updated > held ? r.updated : held;
  }
  for (final a in before.values) {
    if (!present.contains(a.id)) removed[a.id] = now;
  }
  // A mark that is here again was put back after it was removed: its new stamp wins.
  removed.removeWhere((id, _) => present.contains(id));
  // No file before means no notes before: empty notes stay unstamped.
  final same = (previous?.notes ?? '') == next.notes;
  return NotesFile(
    notes: next.notes,
    annotations: annotations,
    notesUpdated: same ? (previous?.notesUpdated ?? next.notesUpdated) : now,
    removed: [for (final MapEntry(:key, :value) in removed.entries) Removal(key, value)],
  );
}

/// A mark's content as JSON, without the time of the change, for telling whether it changed.
String encodeMark(Annotation a) => a.unstamped.toJson().toString();

Annotation _withTime(Annotation a, num? updated) =>
    updated == null ? a.unstamped : a.unstamped.copyWith(updated: updated);

/// Two devices' notes made into one. Marks are kept by id from both sides, a mark changed on both
/// takes the later change, a removal beats a mark that was not changed after it, and the general
/// notes take the later text. The result does not depend on which side is `a`, apart from the
/// order, which keeps `a`'s marks first.
NotesFile mergeNotes(NotesFile a, NotesFile b) {
  final removed = <String, num>{};
  for (final r in [...a.removed, ...b.removed]) {
    final held = removed[r.id];
    removed[r.id] = held == null || r.updated > held ? r.updated : held;
  }
  final live = <String, Annotation>{};
  final order = <String, int>{};
  var n = 0;
  for (final mark in [...a.annotations, ...b.annotations]) {
    order.putIfAbsent(mark.id, () => n++);
    final held = live[mark.id];
    // On a tie, the one that sorts later in its JSON, so that both sides agree.
    final later =
        held == null ||
        _stamp(mark) > _stamp(held) ||
        (_stamp(mark) == _stamp(held) && encodeMark(mark).compareTo(encodeMark(held)) > 0);
    if (later) live[mark.id] = mark;
  }
  for (final id in live.keys.toList()) {
    final removedAt = removed[id];
    if (removedAt == null) continue;
    if (_stamp(live[id]!) > removedAt) {
      removed.remove(id);
    } else {
      live.remove(id);
    }
  }
  final annotations = live.values.toList()..sort((x, y) => order[x.id]! - order[y.id]!);
  final aTime = a.notesUpdated ?? 0;
  final bTime = b.notesUpdated ?? 0;
  final takeA = aTime != bTime ? aTime > bTime : a.notes.compareTo(b.notes) >= 0;
  final winner = takeA ? a : b;
  return NotesFile(
    notes: winner.notes,
    annotations: annotations,
    notesUpdated: winner.notesUpdated,
    removed: [for (final MapEntry(:key, :value) in removed.entries) Removal(key, value)],
  );
}

// Port of the desktop's src/renderer/src/reader.ts. The audio comes ready from the desktop, so
// preparing a sentence means loading its file into a player, and the two ahead are loaded early.
import 'dart:async';

import 'shared/read_plan.dart';
import 'shared/utterances.dart';
import 'shared/types.dart';

enum ReaderState { idle, playing, paused }

/// A position in the document: the n-th planned sentence of a page.
typedef Cursor = ({int page, int index});

/// A sentence's audio, loaded and ready to start.
abstract interface class PreparedAudio {
  /// When each word starts, if the audio itself had to be measured (the phone's voice); null to
  /// use the sentence's own, which the desktop measured.
  List<WordTiming>? get timings;

  /// Plays from the start at `speed`; completes when it ends or is stopped.
  Future<void> play(double speed, void Function(Duration position) onPosition);
  Future<void> pause();
  Future<void> resume();
  Future<void> setSpeed(double speed);
  Future<void> stop();
  Future<void> dispose();
}

abstract interface class SentenceAudio {
  Future<PreparedAudio> prepare(PlannedSentence sentence);
}

abstract interface class ReaderHost {
  int get pageCount;
  Future<List<PlannedSentence>> sentences(int page);

  /// `word` is -1 while the sentence is being prepared or before its first word.
  void onChange(ReaderState state, PlannedSentence? sentence, int word);
  void onError(Object error);
}

const _cacheSize = 6;
const _lookahead = 2;

/// Reads the document aloud sentence by sentence and reports which word is being spoken.
class Reader {
  Reader(
    this.host,
    this.audio, {
    this.gap = const Duration(milliseconds: 80),
    this.headingGap = const Duration(milliseconds: 350),
  });

  final ReaderHost host;
  final SentenceAudio audio;
  // shortcut: one player per sentence adds about 220 ms to each join on the S20 FE, so a join is
  // about 300 ms. If that is heard as too slow, play a gapless playlist with silences instead.
  final Duration gap;
  final Duration headingGap;

  ReaderState state = ReaderState.idle;
  Cursor? cursor;
  double _speed = 1;

  /// Reading ends at the reference list's heading, unless it was started there.
  bool stopAtReferences = false;

  /// Bumped whenever playback is redirected, so a superseded loop notices and exits.
  int _run = 0;
  PreparedAudio? _playing;

  /// The cache key of the playing sentence, whose player is spent once it was started.
  String? _playingKey;
  Completer<void>? _resumed;
  final _cache = <String, Future<PreparedAudio>>{};

  double get speed => _speed;

  set speed(double value) {
    _speed = value;
    unawaited(_playing?.setSpeed(value));
  }

  /// Starts at `start` when idle, otherwise pauses or resumes.
  void toggle(Cursor start) {
    switch (state) {
      case ReaderState.idle:
        unawaited(_loop(start));
      case ReaderState.playing:
        state = ReaderState.paused;
        _resumed = Completer();
        unawaited(_playing?.pause());
        host.onChange(state, null, -1);
      case ReaderState.paused:
        state = ReaderState.playing;
        _resumed?.complete();
        _resumed = null;
        unawaited(_playing?.resume());
        host.onChange(state, null, -1);
    }
  }

  void startAt(Cursor at) => unawaited(_loop(at));

  Future<void> skip(int direction) async {
    final at = cursor;
    if (at == null) return;
    final target = await _settle((page: at.page, index: at.index + direction), direction);
    if (target != null) unawaited(_loop(target));
  }

  void stop() {
    _cancel();
    cursor = null;
    state = ReaderState.idle;
    host.onChange(state, null, -1);
  }

  /// Stops and lets go of every loaded player.
  Future<void> dispose() async {
    stop();
    for (final prepared in _cache.values) {
      unawaited(prepared.then((p) => p.dispose(), onError: (_) {}));
    }
    _cache.clear();
  }

  void _cancel() {
    _run++;
    unawaited(_playing?.stop());
    _playing = null;
    // A new loop must load the stopped sentence afresh; the old loop disposes this player.
    if (_playingKey != null) unawaited(_cache.remove(_playingKey));
    _playingKey = null;
    _resumed?.complete();
    _resumed = null;
  }

  /// Moves a cursor onto an existing sentence, crossing page boundaries in `direction`.
  Future<Cursor?> _settle(Cursor at, int direction) async {
    var page = at.page;
    // Null stands for a page's last sentence. The desktop uses -1 for it, which makes "previous"
    // on a page's first sentence land on that page's last one.
    int? index = at.index;
    if (index < 0) {
      page -= 1;
      index = null;
    }
    while (page >= 1 && page <= host.pageCount) {
      final count = (await host.sentences(page)).length;
      final i = index ?? count - 1;
      if (i >= 0 && i < count) return (page: page, index: i);
      page += direction;
      index = direction == 1 ? 0 : null;
    }
    return null;
  }

  String _key(Cursor at) => '${at.page}:${at.index}';

  Future<PreparedAudio> _prepare(Cursor at, PlannedSentence sentence) {
    final key = _key(at);
    final cached = _cache[key];
    if (cached != null) return cached;
    final prepared = audio.prepare(sentence);
    // A failed load is tried again next time; the error itself reaches whoever awaits it.
    prepared.then(
      (_) {},
      onError: (Object _) {
        if (identical(_cache[key], prepared)) _cache.remove(key);
      },
    );
    _cache[key] = prepared;
    if (_cache.length > _cacheSize) {
      final oldest = _cache.keys.first;
      unawaited(_cache.remove(oldest)!.then((p) => p.dispose(), onError: (_) {}));
    }
    return prepared;
  }

  /// Loads the next two sentences so playback continues without a gap.
  Future<void> _prefetch(Cursor from) async {
    Cursor? at = from;
    for (var i = 0; i < _lookahead && at != null; i++) {
      at = await _settle((page: at.page, index: at.index + 1), 1);
      if (at != null) {
        unawaited(_prepare(at, (await host.sentences(at.page))[at.index]).then((_) {}, onError: (_) {}));
      }
    }
  }

  Future<void> _loop(Cursor start) async {
    _cancel();
    final run = _run;
    state = ReaderState.playing;
    try {
      PlannedSentence? previous;
      var at = await _settle(start, 1);
      while (at != null && run == _run) {
        cursor = at;
        final sentence = (await host.sentences(at.page))[at.index];
        final text = sentence.words.map((w) => w.text).join(' ');
        if (previous != null && stopAtReferences && isReferenceHeading(text)) break;
        host.onChange(state, sentence, -1);
        final pending = _prepare(at, sentence);
        unawaited(_prefetch(at));
        final prepared = await pending;
        if (run != _run) return;
        final pause = sentence.role == Role.heading || previous?.role == Role.heading ? headingGap : gap;
        await Future<void>.delayed(pause * (1 / _speed));
        while (_resumed != null && run == _run) {
          await _resumed!.future;
        }
        if (run != _run) return;
        _playing = prepared;
        _playingKey = _key(at);
        var word = -1;
        final timings = prepared.timings ?? sentence.timings;
        await prepared.play(_speed, (position) {
          if (run != _run) return;
          final seconds = position.inMicroseconds / 1e6;
          var next = word;
          while (next + 1 < timings.length && timings[next + 1].start <= seconds) {
            next++;
          }
          if (next != word) host.onChange(state, sentence, word = next);
        });
        // Played once; going back to it loads it again.
        if (identical(_cache[_key(at)], pending)) unawaited(_cache.remove(_key(at)));
        unawaited(prepared.dispose());
        if (run != _run) return;
        _playing = null;
        _playingKey = null;
        previous = sentence;
        at = await _settle((page: at.page, index: at.index + 1), 1);
      }
      if (run == _run) stop();
    } catch (error) {
      if (run != _run) return;
      stop();
      host.onError(error);
    }
  }
}

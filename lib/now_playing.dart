// The open document as the app's one reading session (PLAN 9.4): its reader stays alive while the
// user looks at the tabs, and the bar above the navigation bar controls it. The same bar sits in the
// reader (PLAN 11), and a tap on either opens the full-screen player.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'favourites_store.dart';
import 'library.dart';
import 'reader.dart';
import 'shared/read_plan.dart';
import 'shared/types.dart';

class ReadingSession extends ChangeNotifier {
  ReadingSession({
    required this.name,
    required this.data,
    required this.placeKey,
    this.prepared,
    this.phoneLangs = const {},
    this.canDictate = false,
    this.startInReading = false,
  });

  /// The languages the phone's own voice speaks (ADR 5); with one, any document can be read.
  final Set<Lang> phoneLangs;

  /// Whether this phone can turn speech into a comment offline (ADR 6).
  final bool canDictate;

  /// The PDF came from another app and opens in the reading view.
  final bool startInReading;

  final String name;
  final Uint8List data;
  final String placeKey;
  final LibraryDocument? prepared;

  ReaderState state = ReaderState.idle;

  /// The sentence being read and its spoken word (-1 before the first); null while nothing is read.
  PlannedSentence? sentence;
  int word = -1;

  /// Where the audio of the sentence being read comes from; null while nothing is read.
  SpeechSource? get source => sentence?.source;

  /// The text of the sentences either side of the one being read, for the player's preview.
  String? previousText;
  String? nextText;

  double speed = 1;

  /// False for a PDF the desktop has not prepared, or has voiced no page of yet, when the phone has
  /// no voice either: there is nothing to play, so no player is shown for it.
  bool get hasAudio => phoneLangs.isNotEmpty || (prepared != null && prepared!.manifest.voiced.isNotEmpty);

  /// Set by the reader once it can read aloud; null for a document the desktop has not prepared.
  VoidCallback? toggle;
  void Function(int direction)? skip;
  void Function(double speed)? setSpeed;

  /// Pauses and asks for a comment on the sentence being read; `speak` starts listening at once.
  Future<void> Function({required bool speak})? comment;

  void update(ReaderState state, {PlannedSentence? sentence, int word = -1}) {
    this.state = state;
    this.sentence = sentence;
    this.word = word;
    notifyListeners();
  }

  void updateNeighbours(String? previous, String? next) {
    previousText = previous;
    nextText = next;
    notifyListeners();
  }

  void updateSpeed(double speed) {
    this.speed = speed;
    notifyListeners();
  }
}

/// One line: play or pause, the title, the heart and the next sentence. A tap opens the player; in
/// the app frame a swipe ends the session.
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({
    super.key,
    required this.session,
    required this.onOpen,
    this.onClose,
    this.favourites,
    this.playKey = const Key('mini-play'),
    this.barKey = const Key('now-playing'),
  });

  final ReadingSession session;
  final VoidCallback onOpen;

  /// Called when the bar is swiped away; null where the bar cannot be dismissed (in the reader).
  final VoidCallback? onClose;
  final FavouritesStore? favourites;
  final Key playKey;
  final Key barKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final docId = session.prepared?.manifest.docId;
    final bar = Padding(
      // Rounded like the reader's play bar, a little apart from the navigation bar.
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: barKey,
          onTap: onOpen,
          child: ListenableBuilder(
            listenable: session,
            builder: (context, _) {
              final playing = session.state == ReaderState.playing;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      key: playKey,
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      tooltip: playing ? 'Pause' : 'Read aloud',
                      onPressed: session.toggle,
                    ),
                    Expanded(
                      child: Text(
                        session.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (favourites case final favourites? when docId != null)
                      ValueListenableBuilder(
                        valueListenable: favourites,
                        builder: (context, value, _) => IconButton(
                          key: const Key('mini-like'),
                          icon: Icon(value.isLiked(docId) ? Icons.favorite : Icons.favorite_border),
                          tooltip: value.isLiked(docId) ? 'Unlike' : 'Like',
                          onPressed: () => favourites.change((f) => f.toggleLike(docId)),
                        ),
                      ),
                    IconButton(
                      key: const Key('mini-next'),
                      icon: const Icon(Icons.skip_next),
                      tooltip: 'Next sentence',
                      onPressed: session.skip == null ? null : () => session.skip!(1),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    final onClose = this.onClose;
    return onClose == null
        ? bar
        : Dismissible(key: ObjectKey(session), onDismissed: (_) => onClose(), child: bar);
  }
}

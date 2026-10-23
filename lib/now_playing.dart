// The open document as the app's one reading session (PLAN 9.4): its reader stays alive while the
// user looks at the tabs, and the bar above the navigation bar controls it.
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
    this.startInReading = false,
  });

  /// The languages the phone's own voice speaks (ADR 5); with one, any document can be read.
  final Set<Lang> phoneLangs;

  /// The PDF came from another app and opens in the reading view.
  final bool startInReading;

  final String name;
  final Uint8List data;
  final String placeKey;
  final LibraryDocument? prepared;

  ReaderState state = ReaderState.idle;

  /// Where the audio of the sentence being read comes from; null while nothing is read.
  SpeechSource? source;

  /// False for a PDF the desktop has not prepared, or has voiced no page of yet, when the phone has
  /// no voice either: there is nothing to play, so no player is shown for it.
  bool get hasAudio => phoneLangs.isNotEmpty || (prepared != null && prepared!.manifest.voiced.isNotEmpty);

  /// Set by the reader once it can read aloud; null for a document the desktop has not prepared.
  VoidCallback? toggle;
  void Function(int direction)? skip;

  void update(ReaderState state, [SpeechSource? source]) {
    this.state = state;
    this.source = source;
    notifyListeners();
  }
}

/// Says where the sentence being read gets its audio: the desktop's, or the phone's own voice.
class AudioSourceBadge extends StatelessWidget {
  const AudioSourceBadge(this.source, {super.key, this.color, this.size = 20});

  final SpeechSource source;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final desktop = source == SpeechSource.desktop;
    return Tooltip(
      message: desktop ? 'Audio prepared on the computer' : 'Spoken by this phone’s voice',
      child: Icon(
        desktop ? Icons.computer : Icons.smartphone,
        key: Key(desktop ? 'source-desktop' : 'source-phone'),
        size: size,
        color: color,
      ),
    );
  }
}

/// One line: play or pause, the title, the heart and the next sentence. A tap opens the reader;
/// a swipe ends the session.
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({
    super.key,
    required this.session,
    required this.onOpen,
    required this.onClose,
    this.favourites,
  });

  final ReadingSession session;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final FavouritesStore? favourites;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final docId = session.prepared?.manifest.docId;
    return Dismissible(
      key: ObjectKey(session),
      onDismissed: (_) => onClose(),
      // Rounded like the reader's play bar, a little apart from the navigation bar.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
        child: Material(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('now-playing'),
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
                        key: const Key('mini-play'),
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                        tooltip: playing ? 'Pause' : 'Read aloud',
                        onPressed: session.toggle,
                      ),
                      Expanded(child: Text(session.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (session.source case final source?) AudioSourceBadge(source),
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
      ),
    );
  }
}

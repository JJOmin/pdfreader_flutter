// The full-screen player (PLAN 11), opened by a tap on the small bar in the menu or in the reader.
// Made to be run without looking: three large playback buttons in the lower two fifths, and big
// targets for the speed and for commenting. The upper part shows the sentence in large type.
import 'package:flutter/material.dart';

import 'now_playing.dart';
import 'reader.dart';
import 'shared/player_preview.dart';
import 'shared/read_plan.dart';
import 'views/speed_reader.dart';

/// Slides the player up over the whole app and back down, like a music app's now-playing screen.
class PlayerLayer extends StatefulWidget {
  const PlayerLayer({
    super.key,
    required this.open,
    required this.session,
    required this.onMinimize,
    required this.onOpenText,
  });

  final bool open;
  final ReadingSession session;
  final VoidCallback onMinimize;
  final VoidCallback onOpenText;

  @override
  State<PlayerLayer> createState() => _PlayerLayerState();
}

class _PlayerLayerState extends State<PlayerLayer> with SingleTickerProviderStateMixin {
  late final _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: widget.open ? 1 : 0,
  );

  @override
  void didUpdateWidget(PlayerLayer old) {
    super.didUpdateWidget(old);
    if (widget.open != old.open) {
      if (widget.open) {
        _slide.forward();
      } else {
        _slide.reverse();
      }
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _slide,
    // Nothing is built while the player is down.
    builder: (context, _) => _slide.isDismissed
        ? const SizedBox.shrink()
        : FractionalTranslation(
            translation: Offset(0, 1 - Curves.easeOutCubic.transform(_slide.value)),
            child: PlayerScreen(
              session: widget.session,
              onMinimize: widget.onMinimize,
              onOpenText: widget.onOpenText,
            ),
          ),
  );
}

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.session, required this.onMinimize, required this.onOpenText});

  final ReadingSession session;

  /// Back to where the player was opened from: the menu or the reader.
  final VoidCallback onMinimize;

  /// Minimises into the reader, whichever view the player was opened from.
  final VoidCallback onOpenText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: session,
          // The text takes whatever the controls leave: they are only as tall as they need to be.
          builder: (context, _) => Column(
            children: [
              _header(context),
              Expanded(
                child: Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 12), child: _preview(context)),
              ),
              _panel(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Row(
    children: [
      IconButton(
        key: const Key('player-minimize'),
        iconSize: 32,
        icon: const Icon(Icons.keyboard_arrow_down),
        tooltip: 'Minimise',
        onPressed: onMinimize,
      ),
      Expanded(
        child: Text(
          session.name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      IconButton(
        key: const Key('player-open-text'),
        icon: const Icon(Icons.article_outlined),
        tooltip: 'Show the text',
        onPressed: onOpenText,
      ),
    ],
  );

  Widget _preview(BuildContext context) {
    final sentence = session.sentence;
    if (sentence == null) {
      return Center(
        child: Text(
          'Press play to start reading',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
      );
    }
    return SpeedReaderWindow(
      words: [for (final w in sentence.words) w.text],
      current: session.word,
      previous: session.previousText,
      next: session.nextText,
    );
  }

  /// The controls on one rounded panel at the bottom, as tall as they need to be and no more.
  Widget _panel(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const Key('player-panel'),
      color: colors.surfaceContainerLow,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _info(context),
              const SizedBox(height: 4),
              _transport(context),
              const SizedBox(height: 8),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  /// Where the audio comes from, in words (an icon would look like a button), and the speed.
  Widget _info(BuildContext context) {
    final sentence = session.sentence;
    final caption = switch (sentence?.source) {
      SpeechSource.desktop => 'Page ${sentence!.page} · computer audio',
      SpeechSource.phone => 'Page ${sentence!.page} · phone voice',
      null => '',
    };
    final setSpeed = session.setSpeed;
    return Row(
      children: [
        Expanded(
          child: Text(
            caption,
            key: const Key('player-source'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          key: const Key('speed-down'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove),
          tooltip: 'Slower',
          onPressed: setSpeed == null ? null : () => setSpeed(steppedSpeed(session.speed, -1)),
        ),
        SizedBox(
          width: 50,
          child: Text(
            '${session.speed.toStringAsFixed(2)}×',
            key: const Key('speed-value'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        IconButton(
          key: const Key('speed-up'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add),
          tooltip: 'Faster',
          onPressed: setSpeed == null ? null : () => setSpeed(steppedSpeed(session.speed, 1)),
        ),
      ],
    );
  }

  Widget _transport(BuildContext context) {
    final playing = session.state == ReaderState.playing;
    final skip = session.skip;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          key: const Key('player-previous'),
          iconSize: 30,
          style: IconButton.styleFrom(fixedSize: const Size(56, 56)),
          icon: const Icon(Icons.skip_previous),
          tooltip: 'Previous sentence',
          onPressed: skip == null ? null : () => skip(-1),
        ),
        const SizedBox(width: 20),
        IconButton.filled(
          key: const Key('player-play'),
          iconSize: 40,
          style: IconButton.styleFrom(fixedSize: const Size(72, 72)),
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          tooltip: playing ? 'Pause' : 'Read aloud',
          onPressed: session.toggle,
        ),
        const SizedBox(width: 20),
        IconButton.filledTonal(
          key: const Key('player-next'),
          iconSize: 30,
          style: IconButton.styleFrom(fixedSize: const Size(56, 56)),
          icon: const Icon(Icons.skip_next),
          tooltip: 'Next sentence',
          onPressed: skip == null ? null : () => skip(1),
        ),
      ],
    );
  }

  Widget _actions() {
    final ready = session.sentence != null && session.comment != null;
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            key: const Key('player-comment'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.edit_note),
            label: const Text('Comment'),
            onPressed: ready ? () => session.comment!(speak: false) : null,
          ),
        ),
        if (session.canDictate) ...[
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.tonalIcon(
              key: const Key('player-dictate'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.mic),
              label: const Text('Speak'),
              onPressed: ready ? () => session.comment!(speak: true) : null,
            ),
          ),
        ],
      ],
    );
  }
}

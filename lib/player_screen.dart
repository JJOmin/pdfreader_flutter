// The full-screen player (PLAN 11), opened by a tap on the small bar in the menu or in the reader.
// Made to be run without looking: large playback buttons at the bottom, and big targets for the speed
// and for commenting. The rest shows the sentence in large type. A short window, as in split screen,
// gets one row of controls; a wide one puts the text and the controls side by side (PLAN 18.5).
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
    required this.onShowMode,
    this.onCovering,
  });

  final bool open;
  final ReadingSession session;
  final VoidCallback onMinimize;
  final ValueChanged<ReaderMode> onShowMode;

  /// Told when the player has come all the way up and covers what is behind it, and when it starts
  /// to go: what it covers need not be painted meanwhile (PLAN 18.1).
  final ValueChanged<bool>? onCovering;

  @override
  State<PlayerLayer> createState() => _PlayerLayerState();
}

class _PlayerLayerState extends State<PlayerLayer> with SingleTickerProviderStateMixin {
  late final _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: widget.open ? 1 : 0,
  )..addStatusListener((status) => widget.onCovering?.call(status == AnimationStatus.completed));

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
              onShowMode: widget.onShowMode,
            ),
          ),
  );
}

/// Below this height the player is in a short window, such as half of a split screen.
const _shortHeight = 560.0;

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.session, required this.onMinimize, required this.onShowMode});

  final ReadingSession session;

  /// Back to where the player was opened from: the menu or the reader.
  final VoidCallback onMinimize;

  /// The switch in the header: the pages or the speed reader minimise the player into the reader.
  final ValueChanged<ReaderMode> onShowMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, box) {
            final short = box.maxHeight < _shortHeight;
            final wide = box.maxWidth >= 600 && box.maxWidth > box.maxHeight * 1.2;
            return ListenableBuilder(
              listenable: session,
              // The text takes whatever the controls leave: they are only as tall as they need to be.
              builder: (context, _) => wide
                  ? Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              _header(context),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
                                  child: _preview(context, short: short),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: (box.maxWidth * 0.42).clamp(320.0, 420.0),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: _panel(context, short: short),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _header(context),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(20, 4, 20, short ? 4 : 12),
                            child: _preview(context, short: short),
                          ),
                        ),
                        _panel(context, short: short),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  /// The title, and under it which page is read and by which audio, in words: an icon would look
  /// like a button. At the right, the switch between the three modes.
  Widget _header(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final sentence = session.sentence;
    final caption = switch (sentence?.source) {
      SpeechSource.desktop => 'Page ${sentence!.page} · computer audio',
      SpeechSource.phone => 'Page ${sentence!.page} · phone voice',
      null => '',
    };
    return Row(
      children: [
        IconButton(
          key: const Key('player-minimize'),
          iconSize: 32,
          icon: const Icon(Icons.keyboard_arrow_down),
          tooltip: 'Minimise',
          onPressed: onMinimize,
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                session.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.bodySmall,
              ),
              Text(
                caption,
                key: const Key('player-source'),
                textAlign: TextAlign.center,
                maxLines: 1,
                style: theme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: SegmentedButton<ReaderMode>(
            key: const Key('player-mode'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
            ),
            segments: const [
              ButtonSegment(
                value: ReaderMode.pages,
                icon: Icon(Icons.picture_as_pdf_outlined, key: Key('player-mode-pages')),
                tooltip: 'Pages',
              ),
              ButtonSegment(
                value: ReaderMode.speedReader,
                icon: Icon(Icons.article_outlined, key: Key('player-mode-reading')),
                tooltip: 'Speed reader',
              ),
              ButtonSegment(
                value: ReaderMode.player,
                icon: Icon(Icons.headphones_outlined, key: Key('player-mode-player')),
                tooltip: 'Player',
              ),
            ],
            selected: const {ReaderMode.player},
            onSelectionChanged: (modes) {
              if (modes.first != ReaderMode.player) onShowMode(modes.first);
            },
          ),
        ),
      ],
    );
  }

  Widget _preview(BuildContext context, {required bool short}) {
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
    final words = [for (final w in sentence.words) w.text];
    // Only this listens to the spoken word, so a new word builds the preview and nothing else.
    return ValueListenableBuilder<int>(
      valueListenable: session.spokenWord,
      builder: (context, word, _) => SpeedReaderWindow(
        words: words,
        current: word,
        // In a short window the sentence alone, a little smaller, so that it can be read.
        previous: short ? null : session.previousText,
        next: short ? null : session.nextText,
        fontSize: short ? 24 : 30,
      ),
    );
  }

  /// The controls on one rounded panel at the bottom, as tall as they need to be and no more. In a
  /// short window the buttons share one row.
  Widget _panel(BuildContext context, {required bool short}) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const Key('player-panel'),
      color: colors.surfaceContainerLow,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, short ? 4 : 8, 16, short ? 4 : 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: short
                ? [_info(context), _transport(context, short: true)]
                : [
                    _info(context),
                    const SizedBox(height: 4),
                    _transport(context, short: false),
                    const SizedBox(height: 8),
                    _actions(),
                  ],
          ),
        ),
      ),
    );
  }

  /// The choice between the computer's audio and the phone's voice, where there is one, and the speed.
  Widget _info(BuildContext context) {
    final setSpeed = session.setSpeed;
    final setVoice = session.setVoice;
    return Row(
      children: [
        if (session.canSwitchVoice)
          SegmentedButton<VoiceChoice>(
            key: const Key('voice-switch'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
            ),
            segments: const [
              ButtonSegment(
                value: VoiceChoice.prepared,
                icon: Icon(Icons.computer, key: Key('voice-prepared')),
                tooltip: 'Audio prepared on the computer',
              ),
              ButtonSegment(
                value: VoiceChoice.phone,
                icon: Icon(Icons.smartphone, key: Key('voice-phone')),
                tooltip: 'This phone’s voice',
              ),
            ],
            selected: {session.voice},
            onSelectionChanged: setVoice == null ? null : (choice) => setVoice(choice.first),
          ),
        const Spacer(),
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

  Widget _transport(BuildContext context, {required bool short}) {
    final playing = session.state == ReaderState.playing;
    final skip = session.skip;
    final side = short ? 48.0 : 56.0;
    final ready = session.sentence != null && session.comment != null;
    return Row(
      mainAxisAlignment: short ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          key: const Key('player-previous'),
          iconSize: short ? 26 : 30,
          style: IconButton.styleFrom(fixedSize: Size(side, side)),
          icon: const Icon(Icons.skip_previous),
          tooltip: 'Previous sentence',
          onPressed: skip == null ? null : () => skip(-1),
        ),
        SizedBox(width: short ? 8 : 20),
        IconButton.filled(
          key: const Key('player-play'),
          iconSize: short ? 32 : 40,
          style: IconButton.styleFrom(fixedSize: Size(side + 8, side + 8) * (short ? 1 : 72 / 64)),
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          tooltip: playing ? 'Pause' : 'Read aloud',
          onPressed: session.toggle,
        ),
        SizedBox(width: short ? 8 : 20),
        IconButton.filledTonal(
          key: const Key('player-next'),
          iconSize: short ? 26 : 30,
          style: IconButton.styleFrom(fixedSize: Size(side, side)),
          icon: const Icon(Icons.skip_next),
          tooltip: 'Next sentence',
          onPressed: skip == null ? null : () => skip(1),
        ),
        // In a short window, Comment and Speak join the same row as icons.
        if (short) ...[
          const SizedBox(width: 8),
          IconButton.filledTonal(
            key: const Key('player-comment'),
            style: IconButton.styleFrom(fixedSize: const Size(48, 48)),
            icon: const Icon(Icons.edit_note),
            tooltip: 'Comment',
            onPressed: ready ? () => session.comment!(speak: false) : null,
          ),
          if (session.canDictate) ...[
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const Key('player-dictate'),
              style: IconButton.styleFrom(fixedSize: const Size(48, 48)),
              icon: const Icon(Icons.mic),
              tooltip: 'Speak a comment',
              onPressed: ready ? () => session.comment!(speak: true) : null,
            ),
          ],
        ],
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

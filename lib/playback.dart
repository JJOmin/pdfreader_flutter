// The platform half of reading aloud: just_audio plays the desktop's Opus files (ADR 2 section 2),
// and audio_service keeps it going with the screen off, with lock-screen controls (step 1.12).
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'library.dart';
import 'reader.dart';
import 'shared/read_plan.dart';

/// How often the word mark asks where the audio is. The player interpolates between its events.
const _tick = Duration(milliseconds: 30);

class _Sentence implements PreparedAudio {
  _Sentence(this._player);

  final AudioPlayer _player;
  final _stopped = Completer<void>();

  @override
  Future<void> play(double speed, void Function(Duration position) onPosition) async {
    await _player.setSpeed(speed);
    final ended = _player.processingStateStream.firstWhere((s) => s == ProcessingState.completed);
    final ticker = Timer.periodic(_tick, (_) => onPosition(_player.position));
    // Returns at once when paused, so the end is taken from the processing state instead.
    unawaited(_player.play());
    try {
      await Future.any([ended, _stopped.future]);
    } finally {
      ticker.cancel();
    }
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.play();

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> stop() async {
    if (!_stopped.isCompleted) _stopped.complete();
    await _player.pause();
  }

  @override
  Future<void> dispose() => _player.dispose();
}

/// Loads a sentence's file into a player of its own, so the next ones are ready before they start.
class LibraryAudio implements SentenceAudio {
  LibraryAudio(this.document);

  final LibraryDocument document;

  @override
  Future<PreparedAudio> prepare(PlannedSentence sentence) async {
    final player = AudioPlayer();
    try {
      await player.setFilePath(document.audioPath(sentence.key));
    } catch (_) {
      await player.dispose();
      rethrow;
    }
    return _Sentence(player);
  }
}

/// The media notification and lock screen: their buttons call into whatever reader is open.
class ReadingHandler extends BaseAudioHandler {
  void Function()? onPlay;
  void Function()? onPause;
  void Function(int direction)? onSkip;
  void Function()? onStop;

  @override
  Future<void> play() async => onPlay?.call();

  @override
  Future<void> pause() async => onPause?.call();

  @override
  Future<void> skipToNext() async => onSkip?.call(1);

  @override
  Future<void> skipToPrevious() async => onSkip?.call(-1);

  @override
  Future<void> stop() async => onStop?.call();

  /// Shows the reader's state where the system shows media.
  void show(ReaderState state, String title, int page) {
    if (state == ReaderState.idle) {
      playbackState.add(PlaybackState(processingState: AudioProcessingState.idle));
      return;
    }
    mediaItem.add(MediaItem(id: title, title: title, album: 'Page $page'));
    final playing = state == ReaderState.playing;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.ready,
        playing: playing,
      ),
    );
  }
}

Future<ReadingHandler> initPlayback() => AudioService.init(
  builder: ReadingHandler.new,
  config: const AudioServiceConfig(
    androidNotificationChannelId: 'io.github.jjomin.pdfreader.reading',
    androidNotificationChannelName: 'Reading aloud',
    // Stays a foreground service while paused, so Play on the lock screen can start it again
    // (Android 12 forbids starting one from the background).
    androidStopForegroundOnPause: false,
  ),
);

// The platform half of reading aloud: just_audio plays the desktop's Opus files (ADR 2 section 2),
// and audio_service keeps it going with the screen off, with lock-screen controls (step 1.12).
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'library.dart';
import 'phone_voice.dart';
import 'reader.dart';
import 'shared/align.dart';
import 'shared/read_plan.dart';
import 'shared/types.dart';

/// How often the word mark asks where the audio is. The player interpolates between its events.
const _tick = Duration(milliseconds: 30);

class _Sentence implements PreparedAudio {
  _Sentence(this._player, {this.timings, this.file});

  final AudioPlayer _player;

  @override
  final List<WordTiming>? timings;

  /// The phone voice's audio, which is deleted with the player.
  final File? file;
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
  Future<void> dispose() async {
    await _player.dispose();
    try {
      await file?.delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}

/// Loads a sentence's audio into a player of its own, so the next ones are ready before they start:
/// the desktop's file when there is one, else the phone's voice speaks the sentence into a file.
class LibraryAudio implements SentenceAudio {
  LibraryAudio({this.document, this.voice});

  /// Null for a PDF the desktop has not prepared.
  final LibraryDocument? document;
  final PhoneVoice? voice;

  @override
  Future<PreparedAudio> prepare(PlannedSentence sentence) async {
    if (sentence.source == SpeechSource.phone) return _spoken(sentence);
    final player = AudioPlayer();
    try {
      await player.setFilePath(document!.audioPath(sentence.key));
    } catch (_) {
      await player.dispose();
      rethrow;
    }
    return _Sentence(player);
  }

  Future<PreparedAudio> _spoken(PlannedSentence sentence) async {
    final file = File(await voice!.synthesize(sentence.spoken, sentence.lang));
    final player = AudioPlayer();
    try {
      final length = await player.setFilePath(file.path) ?? player.duration ?? Duration.zero;
      // The engine says nothing about its words, so they are spread over the audio by length.
      final timings = estimateTimings([for (final w in sentence.words) w.text], length.inMicroseconds / 1e6);
      return _Sentence(player, timings: timings, file: file);
    } catch (_) {
      await player.dispose();
      try {
        await file.delete();
      } on FileSystemException {
        // Already gone.
      }
      rethrow;
    }
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

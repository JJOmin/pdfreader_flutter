// PLAN 18.3 on the phone: how far the player's clock, which the word mark follows, runs ahead of what
// is heard, and whether the phone's speech engine says where its words start.
//   flutter test integration_test/timing_test.dart --no-uninstall
// just_audio starts its clock when `play` is called and never asks Android again while playing; a
// change of speed makes Android send ExoPlayer's own position, which follows the sound itself.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pdfreader/phone_voice.dart';
import 'package:pdfreader/playback.dart';
import 'package:pdfreader/shared/types.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the word clock keeps time with the sound', (tester) async {
    final voice = PlatformPhoneVoice();
    final langs = await voice.languages();
    expect(langs, isNotEmpty, reason: 'this phone has an offline voice');
    final lang = langs.contains(Lang.de) ? Lang.de : langs.first;
    final spoken = await voice.synthesize(
      'Das ist ein etwas längerer Satz, damit die Messung lange genug dauert, um etwas zu zeigen.',
      lang,
    );
    // ignore: avoid_print
    print('MARKS ${spoken.marks.length}: ${spoken.marks}');

    /// How far ahead of the sound a clock is `after` the start: the clock's position, less ExoPlayer's
    /// at the same moment. `clock` is the player's own, or the one the reader uses.
    Future<double> lead(Duration after, Duration Function(AudioPlayer) clock) async {
      final player = AudioPlayer();
      await player.setFilePath(spoken.path);
      final events = <PlaybackEvent>[];
      final listening = player.playbackEventStream.listen(events.add);
      unawaited(player.play());
      await Future<void>.delayed(after);
      final at = DateTime.now();
      final heard = clock(player);
      await player.setSpeed(1.001);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final exo = events.last;
      final exoAt = exo.updatePosition - exo.updateTime.difference(at);
      await listening.cancel();
      await player.dispose();
      return (heard - exoAt).inMicroseconds / 1000;
    }

    final raw = <double>[];
    final kept = <double>[];
    for (var run = 0; run < 5; run++) {
      final after = Duration(milliseconds: 400 + run * 300);
      raw.add(await lead(after, (p) => p.position));
      kept.add(await lead(after, heardPosition));
    }
    // ignore: avoid_print
    print('LEAD ms, just_audio: $raw');
    // ignore: avoid_print
    print('LEAD ms, as the reader counts: $kept');
    File(spoken.path).deleteSync();
    // The first measure comes before Android has timed the output, so ExoPlayer still guesses there.
    final settled = kept.skip(2).toList();
    final mean = settled.reduce((a, b) => a + b) / settled.length;
    expect(mean.abs(), lessThan(40), reason: 'the word mark keeps time with the sound: $kept');
    expect(spoken.marks, isNotEmpty, reason: 'this phone’s engine says where its words start');
  });
}

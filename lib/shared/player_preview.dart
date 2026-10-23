// The small pure parts of the full-screen player (PLAN 11): where each word lies in the preview's
// text, and the speed buttons' steps.
import 'read_plan.dart';
import 'settings.dart';

/// Each word's `[start, end)` in the words joined by single spaces, which is how the preview draws
/// them, so the word being spoken can be found in the painted text.
List<(int, int)> wordSpans(List<String> words) {
  final spans = <(int, int)>[];
  var at = 0;
  for (final word in words) {
    spans.add((at, at + word.length));
    at += word.length + 1;
  }
  return spans;
}

String sentenceText(PlannedSentence sentence) => sentence.words.map((w) => w.text).join(' ');

/// The speed `steps` tenths from `speed`, on a multiple of 0.05 and within the allowed speeds.
double steppedSpeed(double speed, int steps) {
  final moved = ((speed + steps * 0.1) * 20).round() / 20;
  return moved.clamp(minSpeed, maxSpeed);
}

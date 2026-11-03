// A setting changed with − and + or typed as a number (PLAN 18.6), for the speed reader's size and
// spacing. The limits are the settings' own: smallest, largest and step.
import 'dart:math' as math;

typedef NumberLimits = (double min, double max, double step);

int _decimals(double step) {
  var places = 0;
  while (places < 6 && ((step * math.pow(10, places)) - (step * math.pow(10, places)).round()).abs() > 1e-9) {
    places++;
  }
  return places;
}

double _onGrid(double value, NumberLimits limits) {
  final places = _decimals(limits.$3);
  return double.parse(value.clamp(limits.$1, limits.$2).toStringAsFixed(places));
}

/// `value` moved one step up (`direction` 1) or down (-1), onto the step's grid and inside the limits.
double stepped(double value, NumberLimits limits, int direction) {
  final (min, _, step) = limits;
  final steps = (value - min) / step;
  // A value between two steps goes to the next one in the direction asked, not two steps further.
  final next = direction > 0 ? (steps + 1e-6).floor() + 1 : (steps - 1e-6).ceil() - 1;
  return _onGrid(min + next * step, limits);
}

/// What the user typed as a number inside the limits, or null if it is not a number. A decimal comma,
/// as German keyboards give it, counts as a point.
double? parsedNumber(String text, NumberLimits limits) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || !value.isFinite) return null;
  return _onGrid(value, limits);
}

/// The value with as many decimals as the step has.
String shownNumber(double value, NumberLimits limits) => value.toStringAsFixed(_decimals(limits.$3));

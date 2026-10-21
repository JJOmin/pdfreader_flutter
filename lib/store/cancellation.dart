import 'dart:async';

/// Thrown when the user cancels something that was waiting, such as a sign-in.
class CancelledException implements Exception {
  const CancelledException([this.message = 'Cancelled']);

  final String message;

  @override
  String toString() => message;
}

/// What a long wait looks at to know it should stop: the user pressed Cancel.
class Cancellation {
  final _done = Completer<void>();

  bool get isCancelled => _done.isCompleted;

  /// Completes when cancelled, for waits that should end at once.
  Future<void> get whenCancelled => _done.future;

  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const CancelledException();
  }

  /// Waits `duration`, or less if cancelled; throws if it was.
  Future<void> delay(Duration duration) async {
    await Future.any([Future<void>.delayed(duration), whenCancelled]);
    throwIfCancelled();
  }
}

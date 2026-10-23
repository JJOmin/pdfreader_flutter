// Turns recorded speech into text on the phone (ADR 6): sherpa-onnx with the multilingual NeMo CTC
// model of the speech spike (English and German, no network). The model needs a second or two to load
// and the decode blocks, so both happen in an isolate that lives while comments are being spoken and
// is let go after a pause, which frees the model's memory.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'catalog.dart';
import 'engines.dart';
import 'model_files.dart';

abstract interface class Transcriber {
  /// Null when it can transcribe, else a sentence for the user on what is missing.
  Future<String?> problem();

  /// Starts loading the model, so the first words are not waited for.
  Future<void> warmUp();

  /// The text of 16 kHz mono samples; empty when nothing was understood.
  Future<String> transcribe(Float32List samples);
}

/// How long the model stays loaded after the last use.
const _keepLoaded = Duration(seconds: 90);

void _worker((SendPort, String) start) {
  final (out, dir) = start;
  try {
    sherpa.initBindings();
    final recogniser = createAligner(dir);
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    inbox.listen((message) {
      final (id, samples) = message as (int, Float32List);
      try {
        final stream = recogniser.createStream()..acceptWaveform(samples: samples, sampleRate: 16000);
        recogniser.decode(stream);
        final text = recogniser.getResult(stream).text;
        stream.free();
        out.send((id, text, null));
      } catch (error) {
        out.send((id, null, '$error'));
      }
    });
  } catch (error) {
    out.send('$error');
  }
}

class SherpaTranscriber implements Transcriber {
  SherpaTranscriber({this.locate = _locate});

  /// Where the model is installed, or null.
  final Future<String?> Function() locate;

  Future<({SendPort send, Isolate isolate, ReceivePort receive})>? _starting;
  final _pending = <int, Completer<String>>{};
  int _next = 0;
  Timer? _release;

  static Future<String?> _locate() async {
    final folder = await modelsFolder();
    if (folder == null) return null;
    return installedDir(folder, catalog.firstWhere((m) => m.id == 'aligner'));
  }

  @override
  Future<String?> problem() async => await locate() == null
      ? 'The speech model is not on this phone. Copy it there with tool/push_models, or type the comment.'
      : null;

  @override
  Future<void> warmUp() => _worker$().then((_) {}, onError: (Object _) {});

  Future<({SendPort send, Isolate isolate, ReceivePort receive})> _worker$() => _starting ??= _spawn();

  Future<({SendPort send, Isolate isolate, ReceivePort receive})> _spawn() async {
    final dir = await locate();
    if (dir == null) throw StateError('The speech model is not installed');
    final receive = ReceivePort();
    final ready = Completer<SendPort>();
    receive.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (message is String) {
        if (!ready.isCompleted) ready.completeError(StateError(message));
      } else if (message is (int, String?, String?)) {
        final (id, text, error) = message;
        final waiting = _pending.remove(id);
        if (error != null) {
          waiting?.completeError(StateError(error));
        } else {
          waiting?.complete(text ?? '');
        }
      }
    });
    final isolate = await Isolate.spawn(_worker, (receive.sendPort, dir));
    try {
      return (send: await ready.future, isolate: isolate, receive: receive);
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      receive.close();
      _starting = null;
      rethrow;
    }
  }

  @override
  Future<String> transcribe(Float32List samples) async {
    final worker = await _worker$();
    _release?.cancel();
    final id = _next++;
    final done = _pending[id] = Completer<String>();
    worker.send.send((id, _padded(samples)));
    try {
      return _tidy(await done.future);
    } finally {
      _release?.cancel();
      _release = Timer(_keepLoaded, _unload);
    }
  }

  void _unload() {
    final starting = _starting;
    _starting = null;
    starting?.then((w) {
      w.isolate.kill(priority: Isolate.immediate);
      w.receive.close();
    });
  }
}

/// Quiet before and after the speech. The model loses or garbles the first word when speech starts
/// at the very first sample ("Thishi is a comment"); a moment of silence in front stops that.
const _padSamples = 16000 * 4 ~/ 10;

Float32List _padded(Float32List samples) {
  final out = Float32List(samples.length + 2 * _padSamples);
  out.setAll(_padSamples, samples);
  return out;
}

/// What the recogniser gives, as a sentence to read: trimmed, the first letter capital.
String _tidy(String heard) {
  final text = heard.trim();
  return text.isEmpty ? '' : text[0].toUpperCase() + text.substring(1);
}

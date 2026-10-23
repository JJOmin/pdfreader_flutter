import 'dart:async';

import 'package:flutter/material.dart';

/// One line of text that, when it does not fit, runs through slowly, rests, and starts again.
class Marquee extends StatefulWidget {
  const Marquee(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee> {
  final _scroll = ScrollController();
  var _running = false;

  /// Pixels per second: slow enough to read along.
  static const _speed = 30.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  @override
  void didUpdateWidget(Marquee old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text && _scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    while (mounted) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || !_scroll.hasClients) break;
      final end = _scroll.position.maxScrollExtent;
      if (end <= 0) continue;
      await _scroll.animateTo(
        end,
        duration: Duration(milliseconds: (end / _speed * 1000).round()),
        curve: Curves.linear,
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    }
    _running = false;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: _scroll,
    scrollDirection: Axis.horizontal,
    physics: const NeverScrollableScrollPhysics(),
    child: Text(widget.text, style: widget.style, maxLines: 1, softWrap: false),
  );
}

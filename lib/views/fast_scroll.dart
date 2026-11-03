import 'package:flutter/material.dart';

/// How big the grip's touch area is, as Android asks (48 dp); the pill drawn in it is smaller.
const scrollThumbSize = Size(48, 48);

/// The grip of the fast scroller on the right edge: a pill with the page the view is on, in the
/// middle of a 48 dp touch area. Translucent so the text shows through where it passes over it. A
/// screen reader names it and can step it with increase and decrease.
Widget scrollThumbLook(
  BuildContext context,
  Size size,
  String page, {
  VoidCallback? onIncrease,
  VoidCallback? onDecrease,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Semantics(
    label: 'Scroll through the document',
    value: 'page $page',
    increasedValue: 'next',
    decreasedValue: 'previous',
    onIncrease: onIncrease,
    onDecrease: onDecrease,
    child: ExcludeSemantics(
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.92),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))],
          ),
          child: SizedBox(
            width: 40,
            height: 32,
            child: Center(
              child: Text(
                page,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A grip on the right edge for a long document, where flicking takes many tries: the whole height of
/// the view is the whole document. It shows how far through the view is and jumps where it is dragged;
/// the view decides how, since the speed reader builds only what it shows (PLAN 18.2). The pages view
/// has pdfrx's own grip for the same purpose.
class FastScrollThumb extends StatefulWidget {
  const FastScrollThumb({
    super.key,
    required this.listenable,
    required this.fraction,
    required this.onJump,
    required this.label,
    required this.child,
    this.onStep,
  });

  /// Tells the grip that the view moved.
  final Listenable listenable;

  /// How far through the document the view is, 0 to 1; null when there is nothing to scroll.
  final double? Function() fraction;

  /// The grip was dragged to `fraction` of the way through.
  final ValueChanged<double> onJump;

  /// A screen reader's step forward (1) or back (-1).
  final ValueChanged<int>? onStep;

  /// What the grip shows, usually the page the view is on.
  final String Function() label;

  /// The view the grip is laid over.
  final Widget child;

  @override
  State<FastScrollThumb> createState() => _FastScrollThumbState();
}

class _FastScrollThumbState extends State<FastScrollThumb> {
  /// Where the finger holds the grip, while it is dragged: the grip follows the finger, not the view.
  double? _dragging;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_moved);
  }

  @override
  void didUpdateWidget(FastScrollThumb old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_moved);
      widget.listenable.addListener(_moved);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_moved);
    super.dispose();
  }

  void _moved() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollMetricsNotification>(
    // The text grows as its pages are read in, and the first layout comes after the first build.
    onNotification: (_) {
      _moved();
      return false;
    },
    child: Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, box) {
              final travel = box.maxHeight - scrollThumbSize.height;
              final at = _dragging ?? widget.fraction();
              if (travel <= 0 || at == null) return const SizedBox.shrink();
              final onStep = widget.onStep;
              return Stack(
                children: [
                  Positioned(
                    right: 2,
                    top: at.clamp(0.0, 1.0) * travel,
                    width: scrollThumbSize.width,
                    height: scrollThumbSize.height,
                    child: GestureDetector(
                      key: const Key('fast-scroll'),
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (_) => _dragging = widget.fraction() ?? 0,
                      onVerticalDragUpdate: (details) {
                        final to = ((_dragging ?? 0) + details.delta.dy / travel).clamp(0.0, 1.0);
                        setState(() => _dragging = to);
                        widget.onJump(to);
                      },
                      onVerticalDragEnd: (_) => setState(() => _dragging = null),
                      onVerticalDragCancel: () => setState(() => _dragging = null),
                      child: scrollThumbLook(
                        context,
                        scrollThumbSize,
                        widget.label(),
                        onIncrease: onStep == null ? null : () => onStep(1),
                        onDecrease: onStep == null ? null : () => onStep(-1),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

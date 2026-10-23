import 'package:flutter/material.dart';

/// The grip of the fast scroller on the right edge: a pill with the page the view is on. Wide enough
/// to catch a thumb, translucent so the text shows through where it passes over it.
Widget scrollThumbLook(BuildContext context, Size size, String label) {
  final scheme = Theme.of(context).colorScheme;
  return DecoratedBox(
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.92),
      border: Border.all(color: scheme.outline.withValues(alpha: 0.5)),
      borderRadius: BorderRadius.circular(size.height / 2),
      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))],
    ),
    child: Center(
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
    ),
  );
}

/// How big the grip is; the pages view and the reading view use the same.
const scrollThumbSize = Size(40, 32);

/// A grip on the right edge that scrolls a [ScrollController] by dragging, for a long document where
/// flicking takes many tries: the whole height of the view is the whole length of the text. The pages
/// view has pdfrx's own for the same purpose.
class FastScrollThumb extends StatefulWidget {
  const FastScrollThumb({super.key, required this.controller, required this.label, required this.child});

  final ScrollController controller;

  /// The scroll view that [controller] drives; the grip is laid over it.
  final Widget child;

  /// What the grip shows, usually the page the view is on.
  final String Function() label;

  @override
  State<FastScrollThumb> createState() => _FastScrollThumbState();
}

class _FastScrollThumbState extends State<FastScrollThumb> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_moved);
  }

  @override
  void didUpdateWidget(FastScrollThumb old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_moved);
      widget.controller.addListener(_moved);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_moved);
    super.dispose();
  }

  void _moved() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final max = controller.hasClients && controller.position.hasContentDimensions
        ? controller.position.maxScrollExtent
        : 0.0;
    return NotificationListener<ScrollMetricsNotification>(
      // The text grows as its pages are read in, and the first layout comes after the first build.
      onNotification: (_) {
        _moved();
        return false;
      },
      child: Stack(
        children: [
          widget.child,
          // A text that fits the screen has nothing to scroll.
          if (max > 0)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, box) {
                  final travel = box.maxHeight - scrollThumbSize.height;
                  if (travel <= 0) return const SizedBox.shrink();
                  final top = (controller.offset / max).clamp(0.0, 1.0) * travel;
                  return Stack(
                    children: [
                      Positioned(
                        right: 2,
                        top: top,
                        width: scrollThumbSize.width,
                        height: scrollThumbSize.height,
                        child: GestureDetector(
                          key: const Key('fast-scroll'),
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: (details) => controller.jumpTo(
                            (controller.offset + details.delta.dy / travel * max).clamp(0.0, max),
                          ),
                          child: scrollThumbLook(context, scrollThumbSize, widget.label()),
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
}

import 'package:flutter/material.dart';
import '../../../pe_system/presentation/widgets/business_widgets.dart';
import 'lookup_widgets.dart';

/// Wide layouts place two successive events in a staggered pair. Each pair
/// measures its cards naturally, so long logs never overlap following events.
class HistoryTimelineItem extends StatelessWidget {
  const HistoryTimelineItem({
    super.key,
    required this.index,
    required this.wide,
    required this.child,
    this.nextChild,
  });
  final int index;
  final bool wide;
  final Widget child;
  final Widget? nextChild;
  static const stagger = 72.0;

  @override
  Widget build(BuildContext context) {
    final c = LookupColors(context);
    return CustomPaint(
      painter: _TimelinePainter(
        color: c.accent,
        surface: c.surface,
        wide: wide,
        first: index == 0,
        hasNext: nextChild != null,
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child:
            wide
                ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: child),
                    const SizedBox(width: 56),
                    Expanded(
                      child:
                          nextChild == null
                              ? const SizedBox()
                              : Padding(
                                padding: const EdgeInsets.only(top: stagger),
                                child: nextChild,
                              ),
                    ),
                  ],
                )
                : Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: child,
                ),
      ),
    );
  }
}

class HistoryTimelineEnd extends StatelessWidget {
  const HistoryTimelineEnd({super.key, required this.wide});
  final bool wide;
  @override
  Widget build(BuildContext context) {
    final c = LookupColors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Align(
        alignment: wide ? Alignment.topCenter : Alignment.topLeft,
        child: Semantics(
          label: bt(context, 'lookup_history_end'),
          child: Icon(Icons.more_horiz, color: c.accent, size: 24),
        ),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.color,
    required this.surface,
    required this.wide,
    required this.first,
    required this.hasNext,
  });
  final Color color;
  final Color surface;
  final bool wide;
  final bool first;
  final bool hasNext;

  @override
  void paint(Canvas canvas, Size size) {
    final x = wide ? size.width / 2 : 12.0;
    const y = 34.0;
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(x, first ? y : 0), Offset(x, size.height), paint);
    void node(double nodeY, double endX) {
      canvas.drawLine(Offset(x, nodeY), Offset(endX, nodeY - 10), paint);
      canvas.drawCircle(Offset(x, nodeY), 7, Paint()..color = surface);
      canvas.drawCircle(Offset(x, nodeY), 7, paint);
      canvas.drawCircle(Offset(x, nodeY), 4, Paint()..color = color);
      canvas.drawCircle(Offset(endX, nodeY - 10), 3, Paint()..color = color);
    }

    node(y, wide ? x - 28 : 32);
    if (wide && hasNext) node(y + HistoryTimelineItem.stagger, x + 28);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      color != old.color ||
      surface != old.surface ||
      wide != old.wide ||
      first != old.first ||
      hasNext != old.hasNext;
}

import 'package:flutter/material.dart';

class ChatEmptyIllustration extends StatelessWidget {
  const ChatEmptyIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(194, 135),
      painter: _ChatEmptyPainter(
        Theme.of(context).brightness == Brightness.dark,
      ),
    );
  }
}

class _ChatEmptyPainter extends CustomPainter {
  const _ChatEmptyPainter(this.dark);

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / 194, size.height / 135);

    final halo = Path()
      ..moveTo(12, 75)
      ..cubicTo(9, 43, 47, 8, 77, 7)
      ..cubicTo(99, 6, 105, 29, 131, 41)
      ..cubicTo(171, 59, 190, 82, 184, 105)
      ..cubicTo(177, 133, 143, 134, 111, 126)
      ..cubicTo(67, 115, 16, 125, 12, 75)
      ..close();
    canvas.drawPath(
      halo,
      Paint()..color = dark ? const Color(0x403F63CA) : const Color(0x246D9EEA),
    );

    _drawBubble(
      canvas,
      const Rect.fromLTWH(41, 69, 61, 44),
      tailOnRight: false,
      colors: dark
          ? const [Color(0xFF629ACF), Color(0xFF31528D)]
          : const [Color(0xFF98DAF6), Color(0xFF39AEE9)],
    );
    _drawBubble(
      canvas,
      const Rect.fromLTWH(60, 29, 94, 69),
      tailOnRight: true,
      colors: dark
          ? const [Color(0xFF93B8FA), Color(0xFF465BCF), Color(0xFF566FEE)]
          : const [Color(0xFFA6D2FF), Color(0xFF4486F4), Color(0xFF4D75ED)],
    );

    for (final x in [88.0, 107.0, 126.0]) {
      final offset = Offset(x, 63);
      canvas.drawCircle(
        offset,
        5.5,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF4F9FF), Color(0xFF8CB0FD)],
          ).createShader(Rect.fromCircle(center: offset, radius: 5.5)),
      );
    }

    final accent = Paint()
      ..color = dark ? const Color(0xFF8EB7FF) : const Color(0xFF3A70EF)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(156, 17), const Offset(159, 8), accent);
    canvas.drawLine(const Offset(165, 22), const Offset(172, 15), accent);
    canvas.drawLine(const Offset(170, 30), const Offset(179, 28), accent);
    canvas.restore();
  }

  void _drawBubble(
    Canvas canvas,
    Rect rect, {
    required bool tailOnRight,
    required List<Color> colors,
  }) {
    final body = RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.height * .29),
    );
    final x = tailOnRight ? rect.right - 16 : rect.left + 12;
    final direction = tailOnRight ? -1.0 : 1.0;
    final tail = Path()
      ..moveTo(x, rect.bottom - 6)
      ..lineTo(x, rect.bottom + 8)
      ..quadraticBezierTo(
        x,
        rect.bottom + 13,
        x + 5 * direction,
        rect.bottom + 9,
      )
      ..lineTo(x + 21 * direction, rect.bottom - 4)
      ..close();
    final bubble = Path.combine(
      PathOperation.union,
      Path()..addRRect(body),
      tail,
    );
    canvas.drawShadow(bubble, const Color(0x80334EA0), 6, false);
    canvas.drawPath(
      bubble,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(rect),
    );
    canvas.drawPath(
      bubble,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0x45C9E1FF),
    );
  }

  @override
  bool shouldRepaint(_ChatEmptyPainter oldDelegate) => oldDelegate.dark != dark;
}

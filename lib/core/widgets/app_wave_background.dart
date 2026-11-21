import 'package:flutter/material.dart';

class AppWaveBackground extends StatelessWidget {
  const AppWaveBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(painter: _WavePainter(dark), child: child);
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter(this.dark);

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final w = size.width;
    final h = size.height;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF141D3B), Color(0xFF0C1123), Color(0xFF111C3A)]
              : const [Color(0xFFE5EDFD), Color(0xFFF7F9FE), Color(0xFFEAF2FF)],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.58, -1.08),
          radius: .9,
          colors: dark
              ? const [Color(0xA04E4BC9), Color(0x004E4BC9)]
              : const [Color(0x866D9EF7), Color(0x006D9EF7)],
        ).createShader(bounds),
    );

    final upper = Path()
      ..moveTo(0, h * .29)
      ..cubicTo(w * .32, h * .23, w * .56, h * .39, w * .84, h * .31)
      ..quadraticBezierTo(w * .93, h * .28, w, h * .27)
      ..lineTo(w, 0)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(
      upper,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0x002E51A0), Color(0x49314DA3)]
              : const [Color(0x00376ED3), Color(0x37376ED3)],
        ).createShader(Rect.fromLTWH(0, 0, w, h * .35)),
    );

    final front = Path()
      ..moveTo(0, h * .87)
      ..cubicTo(w * .28, h * .88, w * .44, h * .89, w * .73, h * .81)
      ..quadraticBezierTo(w * .90, h * .76, w, h * .78)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    final back = Path()
      ..moveTo(0, h * .74)
      ..cubicTo(w * .24, h * .74, w * .40, h * .86, w * .67, h * .83)
      ..quadraticBezierTo(w * .89, h * .81, w, h * .84)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    final waveBounds = Rect.fromLTWH(0, h * .73, w, h * .27);
    for (final (path, crest) in [
      (back, dark ? const Color(0x644768F3) : const Color(0x597CAEF5)),
      (front, dark ? const Color(0x70546BF7) : const Color(0x666593E8)),
    ]) {
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [crest, crest.withValues(alpha: 0)],
          ).createShader(waveBounds),
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => oldDelegate.dark != dark;
}

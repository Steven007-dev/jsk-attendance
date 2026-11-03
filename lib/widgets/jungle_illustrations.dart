import 'package:flutter/material.dart';

/// A native Flutter background inspired by the leafy login scene in the
/// supplied JSK page. It keeps the illustration independent of any web view.
class JungleBackdrop extends StatelessWidget {
  const JungleBackdrop({super.key});

  @override
  Widget build(BuildContext context) => const Positioned.fill(
    child: CustomPaint(painter: _JungleBackdropPainter()),
  );
}

class _JungleBackdropPainter extends CustomPainter {
  const _JungleBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF0E3220),
            Color(0xFF185229),
            Color(0xFF20683A),
            Color(0xFF1B4A2A),
          ],
          stops: <double>[0, .48, .82, 1],
        ).createShader(bounds),
    );

    final glow = Rect.fromCircle(
      center: Offset(size.width * .84, size.height * .04),
      radius: size.width * .9,
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[const Color(0x2BC4E096), Colors.transparent],
        ).createShader(glow),
    );

    _drawVine(canvas, size, .055, 1, .52);
    _drawVine(canvas, size, .145, 1, .38, thin: true);
    _drawVine(canvas, size, .945, -1, .48);
    _drawVine(canvas, size, .855, -1, .35, thin: true);
    _drawFlower(canvas, Offset(size.width * .84, size.height * .66), 5.5);
    _drawFlower(canvas, Offset(size.width * .72, size.height * .84), 3.5);
  }

  void _drawVine(
    Canvas canvas,
    Size size,
    double xFraction,
    double direction,
    double heightFraction, {
    bool thin = false,
  }) {
    final x = size.width * xFraction;
    final vineHeight = size.height * heightFraction;
    final width = thin ? 2.0 : 3.3;
    final path = Path()
      ..moveTo(x, 0)
      ..cubicTo(
        x - 13 * direction,
        vineHeight * .27,
        x + 13 * direction,
        vineHeight * .58,
        x + 1 * direction,
        vineHeight,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF4E7C3A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );

    final leaves = <(double, double, double)>[
      (.17, -1, -.45),
      (.30, 1, .46),
      (.48, -1, -.40),
      (.66, 1, .42),
      (.84, -1, -.36),
    ];
    for (final (fraction, side, angle) in leaves) {
      _drawLeaf(
        canvas,
        Offset(x + side * direction * 9, vineHeight * fraction),
        angle * direction,
        thin ? 16 : 22,
      );
    }
  }

  void _drawLeaf(Canvas canvas, Offset center, double angle, double length) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: length, height: length * .42),
      Paint()..color = const Color(0xFF5FA84A),
    );
    canvas.drawLine(
      Offset(-length * .26, 0),
      Offset(length * .26, 0),
      Paint()
        ..color = const Color(0xFF3C7C42)
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  void _drawFlower(Canvas canvas, Offset center, double radius) {
    final petalPaint = Paint()..color = const Color(0xFFF4A6C1);
    for (var i = 0; i < 5; i++) {
      final angle = i * 1.256637 + 0.25;
      canvas.drawCircle(
        center + Offset.fromDirection(angle, radius * 1.05),
        radius * .72,
        petalPaint,
      );
    }
    canvas.drawCircle(
      center,
      radius * .4,
      Paint()..color = const Color(0xFFE8749A),
    );
  }

  @override
  bool shouldRepaint(covariant _JungleBackdropPainter oldDelegate) => false;
}

/// The sleepy branch-side mascot painted with Flutter canvas primitives.
class SleepyLionIllustration extends StatelessWidget {
  const SleepyLionIllustration({super.key, this.width = 220});
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * 120 / 220,
    child: Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(
          child: CustomPaint(painter: const _SleepyLionPainter()),
        ),
        Positioned(
          left: width * .48,
          top: width * .08,
          child: const Text(
            'z',
            style: TextStyle(
              color: Color(0xFFFFF7D6),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Positioned(
          left: width * .55,
          top: width * -.015,
          child: const Text(
            'z',
            style: TextStyle(
              color: Color(0xFFFFF7D6),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Positioned(
          left: width * .62,
          top: width * -.12,
          child: const Text(
            'z',
            style: TextStyle(
              color: Color(0xFFFFF7D6),
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SleepyLionPainter extends CustomPainter {
  const _SleepyLionPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 220, size.height / 120);

    final branch = Paint()..color = const Color(0xFF7A5230);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 92, 220, 13),
        const Radius.circular(7),
      ),
      branch,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 92, 220, 5),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF8A5A34),
    );

    _ellipse(canvas, 18, 90, 13, 5, const Color(0xFF5FA84A), -14);
    _ellipse(canvas, 205, 90, 13, 5, const Color(0xFF5FA84A), 12);
    _ellipse(canvas, 48, 88, 10, 4, const Color(0xFF6FB558), -18);
    _ellipse(canvas, 176, 89, 10, 4, const Color(0xFF6FB558), 14);

    final tail = Path()
      ..moveTo(164, 70)
      ..quadraticBezierTo(184, 74, 180, 100);
    canvas.drawPath(
      tail,
      Paint()
        ..color = const Color(0xFFC98A3B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    _ellipse(canvas, 180, 102, 5, 8, const Color(0xFF8A5A34));
    _ellipse(canvas, 128, 74, 46, 24, const Color(0xFFC98A3B));
    _ellipse(canvas, 132, 78, 30, 16, const Color(0xFFE8B96B));
    _ellipse(canvas, 158, 80, 18, 16, const Color(0xFFB77A2F));

    _ellipse(canvas, 72, 66, 31, 31, const Color(0xFF8A5A34));
    _ellipse(canvas, 52, 46, 7, 7, const Color(0xFFC98A3B));
    _ellipse(canvas, 92, 46, 7, 7, const Color(0xFFC98A3B));
    _ellipse(canvas, 72, 66, 21, 21, const Color(0xFFC98A3B));
    _ellipse(canvas, 72, 76, 13, 10, const Color(0xFFE8B96B));

    final nose = Path()
      ..moveTo(68, 71)
      ..lineTo(76, 71)
      ..lineTo(72, 75)
      ..close();
    canvas.drawPath(nose, Paint()..color = const Color(0xFF5A3A1E));
    final eyes = Paint()
      ..color = const Color(0xFF2B1B0E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final x in <double>[55, 81]) {
      final eye = Path()
        ..moveTo(x, 62)
        ..quadraticBezierTo(x + 4, 65.5, x + 8, 62);
      canvas.drawPath(eye, eyes);
    }
    final smile = Path()
      ..moveTo(68, 82)
      ..quadraticBezierTo(72, 84.5, 76, 82);
    canvas.drawPath(
      smile,
      Paint()
        ..color = const Color(0xFF2B1B0E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
    _ellipse(canvas, 92, 88, 10, 6.5, const Color(0xFFC98A3B));
    _ellipse(canvas, 112, 90, 10, 6.5, const Color(0xFFB77A2F));
    canvas.restore();
  }

  void _ellipse(
    Canvas canvas,
    double x,
    double y,
    double rx,
    double ry,
    Color color, [
    double rotation = 0,
  ]) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotation * 3.141592653589793 / 180);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SleepyLionPainter oldDelegate) => false;
}

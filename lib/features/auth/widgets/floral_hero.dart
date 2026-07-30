import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/tandem_colors.dart';

/// The oval watercolor bouquet at the top of the sign-in screen.
///
/// Drops in `assets/images/floral_bouquet.png` when that file exists; otherwise
/// paints an equivalent bouquet so the screen always renders.
class FloralHero extends StatelessWidget {
  const FloralHero({super.key, this.assetPath = 'assets/images/floral_bouquet.png'});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    final palette = context.tandem;

    return AspectRatio(
      aspectRatio: 1.28,
      child: ClipOval(
        child: ColoredBox(
          color: palette.paper,
          child: Image.asset(
            assetPath,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => CustomPaint(
              painter: _BouquetPainter(palette),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

/// A leaf or petal placed in normalized (0..1) coordinates of the oval.
class _Sprig {
  const _Sprig(this.x, this.y, this.angle, this.length, this.leaves, this.tone);

  final double x;
  final double y;
  final double angle; // radians, 0 = pointing right
  final double length; // fraction of the shorter side
  final int leaves;

  /// Resolved against the theme palette at paint time.
  final _Leaf tone;
}

/// Foliage and petal tones, resolved from [TandemColors] when painting.
enum _Leaf { mid, deep, pale }

enum _Petal { blush, deep, pale }

class _Bloom {
  const _Bloom(this.x, this.y, this.radius, this.petals, this.angle, this.tone);

  final double x;
  final double y;
  final double radius; // fraction of the shorter side
  final int petals;
  final double angle;
  final _Petal tone;
}

class _BouquetPainter extends CustomPainter {
  const _BouquetPainter(this.palette);

  final TandemColors palette;

  Color _leaf(_Leaf tone) => switch (tone) {
    _Leaf.mid => palette.leaf,
    _Leaf.deep => palette.leafDeep,
    _Leaf.pale => palette.leafPale,
  };

  Color _petal(_Petal tone) => switch (tone) {
    _Petal.blush => palette.blush,
    _Petal.deep => palette.blushDeep,
    _Petal.pale => palette.blushPale,
  };

  // Foliage fanning out behind the blooms, roughly matching the reference:
  // long sprigs to the left and right, shorter fill toward the centre.
  static const _sprigs = <_Sprig>[
    _Sprig(0.18, 0.46, math.pi * 0.92, 0.34, 5, _Leaf.mid),
    _Sprig(0.24, 0.66, math.pi * 0.78, 0.30, 5, _Leaf.deep),
    _Sprig(0.30, 0.30, math.pi * 1.10, 0.26, 4, _Leaf.pale),
    _Sprig(0.44, 0.24, math.pi * 1.32, 0.24, 4, _Leaf.mid),
    _Sprig(0.58, 0.22, math.pi * 1.62, 0.26, 4, _Leaf.deep),
    _Sprig(0.72, 0.30, math.pi * 1.86, 0.28, 5, _Leaf.mid),
    _Sprig(0.80, 0.50, math.pi * 0.06, 0.32, 5, _Leaf.deep),
    _Sprig(0.74, 0.68, math.pi * 0.22, 0.28, 4, _Leaf.pale),
    _Sprig(0.56, 0.76, math.pi * 0.44, 0.24, 4, _Leaf.mid),
    _Sprig(0.38, 0.78, math.pi * 0.60, 0.22, 4, _Leaf.deep),
  ];

  // Open roses, largest through the middle band.
  static const _blooms = <_Bloom>[
    _Bloom(0.22, 0.56, 0.115, 6, 0.3, _Petal.blush),
    _Bloom(0.38, 0.40, 0.130, 6, 1.1, _Petal.pale),
    _Bloom(0.51, 0.52, 0.150, 7, 0.6, _Petal.blush),
    _Bloom(0.66, 0.36, 0.120, 6, 1.9, _Petal.deep),
    _Bloom(0.49, 0.74, 0.125, 6, 0.9, _Petal.blush),
    _Bloom(0.79, 0.40, 0.085, 5, 2.4, _Petal.pale),
  ];

  // Closed buds tucked at the edges.
  static const _buds = <_Bloom>[
    _Bloom(0.70, 0.62, 0.062, 3, 0.5, _Petal.deep),
    _Bloom(0.84, 0.28, 0.052, 3, 2.2, _Petal.blush),
    _Bloom(0.31, 0.72, 0.050, 3, 1.4, _Petal.deep),
    _Bloom(0.62, 0.20, 0.046, 3, 2.8, _Petal.pale),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width, size.height);

    _paintPaper(canvas, size);
    for (final s in _sprigs) {
      _paintSprig(canvas, size, unit, s);
    }
    for (final b in _blooms) {
      _paintBloom(canvas, size, unit, b);
    }
    for (final b in _buds) {
      _paintBud(canvas, size, unit, b);
    }
  }

  /// Warm paper wash with a faint vignette so the oval reads as painted stock.
  void _paintPaper(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = palette.paper);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            palette.paperHighlight,
            palette.paper,
            palette.paperShade,
          ],
          stops: const [0.0, 0.62, 1.0],
        ).createShader(rect),
    );
  }

  void _paintSprig(Canvas canvas, Size size, double unit, _Sprig sprig) {
    final origin = Offset(sprig.x * size.width, sprig.y * size.height);
    final length = sprig.length * unit;
    final dir = Offset(math.cos(sprig.angle), math.sin(sprig.angle));
    // Bow the stem slightly so the sprig looks hand-drawn rather than radial.
    final normal = Offset(-dir.dy, dir.dx);
    final tip = origin + dir * length;
    final control = origin + dir * (length * 0.5) + normal * (length * 0.16);

    canvas.drawPath(
      Path()
        ..moveTo(origin.dx, origin.dy)
        ..quadraticBezierTo(control.dx, control.dy, tip.dx, tip.dy),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.006
        ..strokeCap = StrokeCap.round
        ..color = palette.leafDeep.withValues(alpha: 0.55),
    );

    final leafPaint = Paint()..color = _leaf(sprig.tone).withValues(alpha: 0.85);
    for (var i = 0; i < sprig.leaves; i++) {
      final t = (i + 1) / (sprig.leaves + 1);
      // Point on the quadratic stem at t.
      final point = _quadraticAt(origin, control, tip, t);
      final side = i.isEven ? 1.0 : -1.0;
      final leafLength = length * (0.42 - 0.16 * t);
      final tilt = sprig.angle + side * 0.85;
      _paintLeaf(canvas, point, tilt, leafLength, leafLength * 0.36, leafPaint);
    }

    // A small leaf capping the tip.
    _paintLeaf(canvas, tip, sprig.angle, length * 0.30, length * 0.11, leafPaint);
  }

  Offset _quadraticAt(Offset a, Offset b, Offset c, double t) {
    final u = 1 - t;
    return a * (u * u) + b * (2 * u * t) + c * (t * t);
  }

  /// Pointed lens shape, drawn as two mirrored quadratics.
  void _paintLeaf(
    Canvas canvas,
    Offset base,
    double angle,
    double length,
    double width,
    Paint paint,
  ) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angle);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(length * 0.5, -width, length, 0)
        ..quadraticBezierTo(length * 0.5, width, 0, 0)
        ..close(),
      paint,
    );
    canvas.drawLine(
      Offset.zero,
      Offset(length * 0.92, 0),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 0.09
        ..color = palette.leafDeep.withValues(alpha: 0.35),
    );
    canvas.restore();
  }

  /// Open rose: an outer ring of petals, a tighter inner ring, pollen centre.
  void _paintBloom(Canvas canvas, Size size, double unit, _Bloom bloom) {
    final center = Offset(bloom.x * size.width, bloom.y * size.height);
    final radius = bloom.radius * unit;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(bloom.angle);

    _paintPetalRing(canvas, radius, bloom.petals, 0, _petal(bloom.tone), 0.92);
    _paintPetalRing(
      canvas,
      radius * 0.62,
      bloom.petals,
      math.pi / bloom.petals,
      Color.lerp(_petal(bloom.tone), palette.blushDeep, 0.35)!,
      0.85,
    );

    // Pollen: a warm centre disc ringed with stamen dots.
    canvas.drawCircle(
      Offset.zero,
      radius * 0.20,
      Paint()..color = palette.pollenCentre,
    );
    final dot = Paint()..color = palette.pollen.withValues(alpha: 0.85);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      canvas.drawCircle(
        Offset(math.cos(a), math.sin(a)) * (radius * 0.13),
        radius * 0.035,
        dot,
      );
    }
    canvas.restore();
  }

  void _paintPetalRing(
    Canvas canvas,
    double radius,
    int count,
    double phase,
    Color color,
    double alpha,
  ) {
    final paint = Paint()..color = color.withValues(alpha: alpha);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.03
      ..color = palette.blushDeep.withValues(alpha: 0.30);

    for (var i = 0; i < count; i++) {
      final a = phase + i * 2 * math.pi / count;
      canvas.save();
      canvas.rotate(a);
      final petal = Rect.fromCenter(
        center: Offset(radius * 0.58, 0),
        width: radius * 0.92,
        height: radius * 0.72,
      );
      canvas.drawOval(petal, paint);
      canvas.drawOval(petal, edge);
      canvas.restore();
    }
  }

  /// Closed bud: a teardrop with a sage calyx at its base.
  void _paintBud(Canvas canvas, Size size, double unit, _Bloom bud) {
    final center = Offset(bud.x * size.width, bud.y * size.height);
    final r = bud.radius * unit;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(bud.angle);

    canvas.drawPath(
      Path()
        ..moveTo(0, -r * 1.5)
        ..quadraticBezierTo(r, -r * 0.3, 0, r)
        ..quadraticBezierTo(-r, -r * 0.3, 0, -r * 1.5)
        ..close(),
      Paint()..color = _petal(bud.tone).withValues(alpha: 0.92),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, r * 1.05)
        ..quadraticBezierTo(r * 0.75, r * 0.1, 0, r * 0.25)
        ..quadraticBezierTo(-r * 0.75, r * 0.1, 0, r * 1.05)
        ..close(),
      Paint()..color = palette.leafDeep.withValues(alpha: 0.85),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BouquetPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

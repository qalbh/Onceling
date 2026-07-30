import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A card that rips along a jagged seam and throws the two halves apart.
///
/// Both halves are cut from the same tooth line, so at [progress] 0 they sit
/// perfectly interlocked and read as one card.
class TornCard extends StatelessWidget {
  const TornCard({
    super.key,
    required this.progress,
    required this.child,
    this.teeth = 7,
    this.toothDepth = 16,
    this.radius = 26,
  });

  /// 0 = intact, 1 = fully separated.
  final double progress;
  final Widget child;
  final int teeth;
  final double toothDepth;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final eased = Curves.easeInCubic.transform(progress.clamp(0.0, 1.0));

    return Stack(
      alignment: Alignment.center,
      children: [
        _half(isTop: true, eased: eased),
        _half(isTop: false, eased: eased),
      ],
    );
  }

  Widget _half({required bool isTop, required double eased}) {
    // Top piece drifts up and left, bottom piece down and right.
    final direction = isTop ? -1.0 : 1.0;
    final offset = Offset(
      direction * -60 * eased,
      direction * 150 * eased,
    );

    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: direction * -0.07 * eased,
        child: Opacity(
          opacity: (1 - eased * 0.9).clamp(0.0, 1.0),
          child: ClipPath(
            clipper: _TearClipper(
              isTop: isTop,
              teeth: teeth,
              toothDepth: toothDepth,
              radius: radius,
            ),
            // Both halves paint the whole card and clip to their side, so hide
            // one from screen readers to avoid reading it twice.
            child: isTop ? child : ExcludeSemantics(child: child),
          ),
        ),
      ),
    );
  }
}

class _TearClipper extends CustomClipper<Path> {
  const _TearClipper({
    required this.isTop,
    required this.teeth,
    required this.toothDepth,
    required this.radius,
  });

  final bool isTop;
  final int teeth;
  final double toothDepth;
  final double radius;

  /// Shared seam: the y offset of the tooth at each vertex across the width.
  double _seamY(int index, double mid) {
    // Alternate above/below the midline, with a slight taper at the edges so
    // the rip does not look mechanical.
    final peak = index.isEven ? -toothDepth : toothDepth;
    final taper = math.sin((index / teeth) * math.pi).clamp(0.35, 1.0);
    return mid + peak * taper;
  }

  @override
  Path getClip(Size size) {
    final mid = size.height / 2;
    final path = Path();
    final step = size.width / teeth;

    if (isTop) {
      path
        ..moveTo(0, radius)
        ..arcToPoint(Offset(radius, 0), radius: Radius.circular(radius))
        ..lineTo(size.width - radius, 0)
        ..arcToPoint(
          Offset(size.width, radius),
          radius: Radius.circular(radius),
        )
        ..lineTo(size.width, _seamY(teeth, mid));
      for (var i = teeth - 1; i >= 0; i--) {
        path.lineTo(i * step, _seamY(i, mid));
      }
    } else {
      path.moveTo(0, _seamY(0, mid));
      for (var i = 1; i <= teeth; i++) {
        path.lineTo(i * step, _seamY(i, mid));
      }
      path
        ..lineTo(size.width, size.height - radius)
        ..arcToPoint(
          Offset(size.width - radius, size.height),
          radius: Radius.circular(radius),
        )
        ..lineTo(radius, size.height)
        ..arcToPoint(
          Offset(0, size.height - radius),
          radius: Radius.circular(radius),
        );
    }

    return path..close();
  }

  @override
  bool shouldReclip(_TearClipper oldClipper) =>
      oldClipper.isTop != isTop ||
      oldClipper.teeth != teeth ||
      oldClipper.toothDepth != toothDepth;
}

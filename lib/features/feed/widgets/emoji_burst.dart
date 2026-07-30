import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/tandem_glyphs.dart';

/// Overlay layer that throws emoji up the screen, as in the "burst in flight"
/// mock. Drive it through a [GlobalKey] and call [EmojiBurstLayerState.fire].
class EmojiBurstLayer extends StatefulWidget {
  const EmojiBurstLayer({super.key});

  @override
  State<EmojiBurstLayer> createState() => EmojiBurstLayerState();
}

class EmojiBurstLayerState extends State<EmojiBurstLayer>
    with TickerProviderStateMixin {
  final _bursts = <_Burst>[];
  final _random = math.Random();

  /// Launches [count] copies of [emoji] from [origin] (a global position).
  void fire(String emoji, Offset origin, {int count = 14}) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );

    final box = context.findRenderObject() as RenderBox?;
    final local = box?.globalToLocal(origin) ?? origin;

    final burst = _Burst(
      emoji: emoji,
      controller: controller,
      particles: List.generate(count, (i) {
        return _Particle(
          start: local,
          // Spread horizontally, rise most of the screen, vary the timing so
          // they do not move as one block.
          drift: (_random.nextDouble() - 0.5) * 260,
          rise: 260 + _random.nextDouble() * 420,
          size: 22 + _random.nextDouble() * 22,
          delay: _random.nextDouble() * 0.35,
          spin: (_random.nextDouble() - 0.5) * 0.6,
        );
      }),
    );

    setState(() => _bursts.add(burst));

    controller.forward().whenComplete(() {
      if (mounted) setState(() => _bursts.remove(burst));
      controller.dispose();
    });
  }

  @override
  void dispose() {
    for (final burst in _bursts) {
      burst.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          for (final burst in _bursts)
            for (final particle in burst.particles)
              _ParticleView(
                emoji: burst.emoji,
                particle: particle,
                animation: burst.controller,
              ),
        ],
      ),
    );
  }
}

class _Burst {
  _Burst({
    required this.emoji,
    required this.controller,
    required this.particles,
  });

  final String emoji;
  final AnimationController controller;
  final List<_Particle> particles;
}

class _Particle {
  const _Particle({
    required this.start,
    required this.drift,
    required this.rise,
    required this.size,
    required this.delay,
    required this.spin,
  });

  final Offset start;
  final double drift;
  final double rise;
  final double size;
  final double delay;
  final double spin;
}

class _ParticleView extends AnimatedWidget {
  const _ParticleView({
    required this.emoji,
    required this.particle,
    required Animation<double> animation,
  }) : super(listenable: animation);

  final String emoji;
  final _Particle particle;

  Animation<double> get _animation => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) {
    // Re-base the raw 0..1 clock against this particle's delay.
    final raw = _animation.value;
    final t = ((raw - particle.delay) / (1 - particle.delay)).clamp(0.0, 1.0);
    if (t == 0) return const SizedBox.shrink();

    final eased = Curves.easeOutCubic.transform(t);
    // Sideways sway rather than a straight line.
    final x = particle.start.dx + particle.drift * eased;
    final y = particle.start.dy - particle.rise * eased;
    final wobble = math.sin(t * math.pi * 2) * 12;

    return Positioned(
      left: x + wobble - particle.size / 2,
      top: y - particle.size / 2,
      child: Opacity(
        // Fade in fast, hold, then fade out over the last third.
        opacity: (t < 0.1 ? t / 0.1 : (1 - t) / 0.65).clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: particle.spin * eased,
          child: Glyph(emoji, size: particle.size),
        ),
      ),
    );
  }
}

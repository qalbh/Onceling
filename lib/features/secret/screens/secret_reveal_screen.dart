import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../../../theme/theme_glyphs.dart';
import '../../feed/models/feed_item.dart';
import '../widgets/torn_card.dart';

/// How the reading ended.
class SecretRevealResult {
  const SecretRevealResult({required this.heldFullCountdown});

  /// True when they stayed until the ring emptied rather than closing early.
  final bool heldFullCountdown;
}

/// The full-screen secret takeover: a held breath, the tear, then the reading
/// against a countdown. Once it ends the secret is gone for both people.
class SecretRevealScreen extends StatefulWidget {
  const SecretRevealScreen({super.key, required this.secret});

  final SecretMessage secret;

  /// Opens over the thread, letting it show through the scrim.
  static Future<SecretRevealResult?> show(
    BuildContext context,
    SecretMessage secret,
  ) {
    return Navigator.of(context).push<SecretRevealResult>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, _, _) => SecretRevealScreen(secret: secret),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<SecretRevealScreen> createState() => _SecretRevealScreenState();
}

enum _Stage { heldBreath, tearing, reading }

class _SecretRevealScreenState extends State<SecretRevealScreen>
    with TickerProviderStateMixin {
  static const _heldBreath = Duration(milliseconds: 1400);
  static const _tearDuration = Duration(milliseconds: 900);

  late final AnimationController _tear = AnimationController(
    vsync: this,
    duration: _tearDuration,
  );

  /// Empties over the reading window; drives the ring and the auto-close.
  AnimationController? _countdown;
  Timer? _stageTimer;
  Timer? _closeTimer;
  _Stage _stage = _Stage.heldBreath;

  @override
  void initState() {
    super.initState();
    _stageTimer = Timer(_heldBreath, _startTear);
  }

  @override
  void dispose() {
    _tear.dispose();
    _countdown?.dispose();
    _stageTimer?.cancel();
    _closeTimer?.cancel();
    super.dispose();
  }

  void _startTear() {
    if (!mounted) return;
    setState(() => _stage = _Stage.tearing);
    _tear.forward().whenComplete(_startReading);
  }

  void _startReading() {
    if (!mounted) return;
    setState(() => _stage = _Stage.reading);

    final window = widget.secret.duration.window;
    if (window == null) return; // "until they close it"

    _countdown = AnimationController(vsync: this, duration: window)..forward();
    _closeTimer = Timer(window, () => _finish(heldFull: true));
  }

  void _finish({required bool heldFull}) {
    if (!mounted) return;
    Navigator.of(context).pop(SecretRevealResult(heldFullCountdown: heldFull));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.secretScrim.withValues(alpha: 0.94),
      body: SafeArea(
        // expand: the top bar is the only non-positioned child, so without
        // this the stack would collapse to its height.
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                child: switch (_stage) {
                  _Stage.heldBreath || _Stage.tearing => _sealed(),
                  _Stage.reading => _reading(),
                },
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopBar(
                from: widget.secret.sender,
                countdown: _countdown,
                totalSeconds: widget.secret.duration.window?.inSeconds,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Stages 09 and 10 — the card waiting, then ripping.
  Widget _sealed() {
    return SingleChildScrollView(
      key: const ValueKey('sealed'),
      // Centres normally, but scrolls rather than overflowing when the card is
      // taller than the space (small screens, large text settings).
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _tear,
            builder: (context, _) => TornCard(
              progress: _tear.value,
              child: _SealedCard(from: widget.secret.sender),
            ),
          ),
          const SizedBox(height: 26),
          AnimatedOpacity(
            opacity: _stage == _Stage.tearing ? 0 : 1,
            duration: const Duration(milliseconds: 240),
            child: Text(
              'ONCE IT OPENS, IT IS GONE',
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: context.palette.onScrimFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Stage 11 — the words, then the way out.
  Widget _reading() {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Padding(
      key: const ValueKey('reading'),
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                widget.secret.body,
                style: AppTheme.wordmark(
                  context,
                  26,
                ).copyWith(color: palette.secretPaper, height: 1.42),
              ),
            ),
          ),
          const SizedBox(height: 30),
          Text(
            widget.secret.duration.window == null
                ? 'It disappears for both of us when you close it.'
                : 'It disappears for both of us when the ring empties.',
            style: theme.textTheme.headlineSmall!.copyWith(
              color: palette.onScrimFaint,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton(
              onPressed: () => _finish(heldFull: false),
              style: FilledButton.styleFrom(
                backgroundColor: palette.onScrim.withValues(alpha: 0.14),
                foregroundColor: palette.secretPaper,
                elevation: 0,
                shape: const StadiumBorder(),
                textStyle: AppTheme.bold(theme.textTheme.headlineLarge!),
              ),
              child: const Text('Close now'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The cream card holding the seal, before the tear.
class _SealedCard extends StatelessWidget {
  const _SealedCard({required this.from});

  final Person from;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
      decoration: BoxDecoration(
        color: context.palette.secretPaper,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiary,
              shape: BoxShape.circle,
            ),
            child: Glyph('🔒', size: context.glyphs.revealSeal),
          ),
          const SizedBox(height: 20),
          Text(
            '${from.name} wrote this for you',
            textAlign: TextAlign.center,
            // The card is always paper, so it carries its own ink tone.
            style: AppTheme.wordmark(
              context,
              20,
            ).copyWith(color: context.palette.onSecretPaper),
          ),
        ],
      ),
    );
  }
}

/// "FROM MAYA" on the left, the emptying countdown on the right.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.from,
    required this.countdown,
    required this.totalSeconds,
  });

  final Person from;
  final Animation<double>? countdown;
  final int? totalSeconds;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              'FROM ${from.name.toUpperCase()}',
              style: Theme.of(context).textTheme.labelMedium!.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.8,
                color: Colors.white,
              ),
            ),
          ),
          _CountdownDot(animation: countdown, totalSeconds: totalSeconds),
        ],
      ),
    );
  }
}

class _CountdownDot extends StatelessWidget {
  const _CountdownDot({required this.animation, required this.totalSeconds});

  final Animation<double>? animation;
  final int? totalSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final total = totalSeconds;

    return SizedBox(
      width: 54,
      height: 54,
      child: AnimatedBuilder(
        // Before the reading starts there is no controller yet; show the full
        // window sitting still.
        animation: animation ?? const AlwaysStoppedAnimation(0.0),
        builder: (context, _) {
          final elapsed = animation?.value ?? 0.0;
          final remaining = total == null
              ? null
              : (total * (1 - elapsed)).ceil().clamp(0, total);

          return Stack(
            alignment: Alignment.center,
            children: [
              if (total != null)
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: 1 - elapsed,
                    strokeWidth: 2.5,
                    backgroundColor: palette.onScrim.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(palette.onScrim),
                  ),
                ),
              Container(
                margin: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  remaining?.toString() ?? '∞',
                  style: theme.textTheme.headlineLarge!.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

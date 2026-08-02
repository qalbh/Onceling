import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/providers.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../../../theme/theme_glyphs.dart';
import '../../feed/models/feed_item.dart';
import '../secret_service.dart';
import '../widgets/torn_card.dart';

/// How the reading ended.
class SecretRevealResult {
  const SecretRevealResult({required this.heldFullCountdown});

  /// True when they stayed until the ring emptied rather than closing early.
  ///
  /// Reported by the screen for its own use only. What the SENDER is told is
  /// derived server-side in `completeReveal` from the real elapsed time — an
  /// app about honesty should not let one side author the other side's
  /// notification.
  final bool heldFullCountdown;
}

/// The full-screen secret takeover: a held breath, the tear, then the reading
/// against a countdown. Once it ends the body is destroyed for both people.
///
/// **The screen owns the reveal (P3-01).** It no longer receives a body; it
/// calls `beginReveal`, reads `secretBodies/{itemId}` inside the window the
/// server just opened, and calls `completeReveal` when the reading ends. The
/// body is deliberately never passed in, because the only moment it is legible
/// is between those two calls.
class SecretRevealScreen extends ConsumerStatefulWidget {
  const SecretRevealScreen({
    super.key,
    required this.secret,
    required this.senderName,
  });

  final SecretMessage secret;

  /// Display name for `secret.senderId`, resolved by the caller.
  final String senderName;

  @override
  ConsumerState<SecretRevealScreen> createState() => _SecretRevealScreenState();
}

enum _Stage {
  /// Pure animation, before anything is committed.
  heldBreath,
  tearing,

  /// `beginReveal` in flight, or the body being fetched.
  opening,

  /// The words are on screen and the window is running.
  reading,

  /// The read failed but the window is open — retryable.
  failed,

  /// The window ran out, or the body was already gone.
  expired,

  /// It had already been opened before this screen got there.
  spent,
}

class _SecretRevealScreenState extends ConsumerState<SecretRevealScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _heldBreath = Duration(milliseconds: 1400);
  static const _tearDuration = Duration(milliseconds: 900);

  /// Created eagerly in [initState], including on paths that never tear.
  ///
  /// It used to be a `late final` with an inline initialiser, which meant that
  /// on a path where nothing reads it the field was first constructed inside
  /// [dispose]. Creating a `Ticker` there looks up `TickerMode` on an element
  /// that is already deactivated, which throws.
  late final AnimationController _tear;

  /// Drives the ring. Its value is *elapsed fraction*, written by [_tick] from
  /// the server's window rather than run as an animation — see [_tick].
  late final AnimationController _ring;

  Timer? _stageTimer;
  Timer? _ticker;

  _Stage _stage = _Stage.heldBreath;
  RevealWindow? _window;

  /// The clock, read through a provider so a test can pin it. `tester.pump`
  /// advances fake async time, never the wall clock, so a countdown wired
  /// straight to `DateTime.now()` would be untestable — the ring would sit
  /// still while the test believed thirty seconds had passed.
  DateTime _now() => ref.read(nowProvider)();
  String? _body;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tear = AnimationController(vsync: this, duration: _tearDuration);
    _ring = AnimationController(vsync: this);

    if (widget.secret.isOpened) {
      _stage = _Stage.spent;
      return;
    }
    _stageTimer = Timer(_heldBreath, _startTear);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tear.dispose();
    _ring.dispose();
    _stageTimer?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  /// The window keeps running while the app is backgrounded — it is the
  /// server's clock, not a local timer that pauses.
  ///
  /// So on resume the only correct thing is to recompute from
  /// `openingStartedAt`. A paused local countdown would come back showing time
  /// that no longer exists, and the reader would watch a ring tick down over a
  /// body the rule had already stopped serving.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _stage == _Stage.reading) {
      _tick();
    }
  }

  void _startTear() {
    if (!mounted) return;
    setState(() => _stage = _Stage.tearing);
    _tear.forward().whenComplete(_begin);
  }

  /// Commits. Everything before this point is reversible.
  ///
  /// **This is the answer to Q1's confirmation question, and it is why there is
  /// no dialog.** The held breath and the tear are 2.3 seconds during which
  /// nothing has been written and the secret is still sealed — leaving now
  /// costs nothing. Firing `beginReveal` at the END of that choreography turns
  /// the animation into the confirmation step rather than decoration, which a
  /// modal would only duplicate. A second "are you sure" after a deliberate
  /// press-and-hold is the kind of prompt people learn to dismiss without
  /// reading, and it would break the one moment in the app that is meant to
  /// feel like holding your breath.
  ///
  /// Starting the clock here rather than at the hold also means the reader gets
  /// the whole window for reading, instead of losing 2.3s of it to animation.
  Future<void> _begin() async {
    if (!mounted) return;
    setState(() => _stage = _Stage.opening);

    final service = ref.read(secretServiceProvider);
    try {
      // Idempotent server-side: a retry through here returns the existing
      // window rather than restarting the clock.
      final window = await service.beginReveal(widget.secret.id);
      if (!mounted) return;

      if (window.hasExpiredAt(_now())) {
        setState(() => _stage = _Stage.expired);
        return;
      }

      final body = await service.readBody(widget.secret.id);
      if (!mounted) return;

      setState(() {
        _window = window;
        _body = body;
        _stage = _Stage.reading;
      });
      _startCountdown();
    } on SecretBodyGoneException {
      if (mounted) setState(() => _stage = _Stage.expired);
    } catch (error) {
      if (!mounted) return;
      // The state may well have changed even though the read failed — that is
      // exactly the case this stage exists for. `beginReveal` being idempotent
      // is what makes the retry safe.
      setState(
        () => _stage = _isAlreadyOpened(error)
            ? _Stage.spent
            : _isExpired(error)
            ? _Stage.expired
            : _Stage.failed,
      );
    }
  }

  bool _isAlreadyOpened(Object error) =>
      error.toString().contains('already-opened') ||
      error.toString().contains('Already opened');

  bool _isExpired(Object error) =>
      error.toString().contains('window-expired') ||
      error.toString().contains('window closed');

  void _startCountdown() {
    _tick();
    // 200ms rather than a frame ticker: the ring shows whole seconds, and this
    // recomputes from the server window each time instead of accumulating
    // local drift.
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  void _tick() {
    final window = _window;
    if (!mounted || window == null) return;

    final remaining = window.remainingAt(_now());
    final total = window.window.inMilliseconds;
    // untilClosed reports the server's hour ceiling as its window. The ring
    // still shows no countdown for it — see [_totalSecondsForRing].
    _ring.value = total == 0
        ? 0
        : (1 - remaining.inMilliseconds / total).clamp(0.0, 1.0);

    if (remaining == Duration.zero) {
      _ticker?.cancel();
      _complete(heldFull: true);
    }
  }

  /// Ends the reading and destroys the body.
  ///
  /// Guarded against re-entry: the countdown reaching zero and the reader
  /// tapping Close can both land, and `completeReveal` is idempotent server
  /// side anyway — but popping twice is not.
  Future<void> _complete({required bool heldFull}) async {
    if (_completing) return;
    _completing = true;
    _ticker?.cancel();

    try {
      await ref.read(secretServiceProvider).completeReveal(widget.secret.id);
    } catch (_) {
      // The reading is over either way, and the sweep will finish it if this
      // did not. Failing loudly here would leave the reader staring at a
      // secret they have already read.
    }
    if (!mounted) return;
    Navigator.of(context).pop(SecretRevealResult(heldFullCountdown: heldFull));
  }

  /// Null for `untilClosed`, which makes the ring show `∞`.
  ///
  /// The server does cap those at an hour, but that ceiling is an
  /// anti-retention backstop rather than a reading deadline — no one reads a
  /// secret for an hour. Showing a 3600-second countdown would contradict the
  /// "until they close it" the sender chose, for a limit a real reader never
  /// reaches.
  int? get _totalSecondsForRing => widget.secret.duration.window?.inSeconds;

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
                  _Stage.opening => _opening(),
                  _Stage.reading => _reading(),
                  _Stage.failed => _failed(),
                  _Stage.expired => _expired(),
                  _Stage.spent => _spent(),
                },
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopBar(
                fromName: widget.senderName,
                countdown: _stage == _Stage.reading ? _ring : null,
                totalSeconds: _totalSecondsForRing,
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
              child: _SealedCard(fromName: widget.senderName),
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

  /// The gap between the tear finishing and the words arriving.
  ///
  /// Usually a single frame. It gets a state of its own rather than a blank
  /// because on a slow connection this is where the reader waits, and a blank
  /// scrim reads as the secret having failed.
  Widget _opening() {
    return Center(
      key: const ValueKey('opening'),
      child: Text(
        'Opening…',
        style: AppTheme.wordmark(
          context,
          22,
        ).copyWith(color: context.palette.onScrimFaint),
      ),
    );
  }

  /// The window opened but the words did not arrive.
  ///
  /// Retryable, and honest that the clock is now running: the state changed
  /// even though the read failed, which is the one failure mode that costs the
  /// reader something.
  Widget _failed() => _Panel(
    key: const ValueKey('failed'),
    fromName: widget.senderName,
    title: 'It would not open',
    body:
        'The secret is still there and still yours to read. The countdown '
        'has started, so try again now rather than later.',
    actionLabel: 'Try again',
    onAction: _begin,
    onDismiss: () => Navigator.of(context).pop(),
  );

  /// The window ran out, or the body was already gone.
  Widget _expired() => _Panel(
    key: const ValueKey('expired'),
    fromName: widget.senderName,
    title: 'This one is gone',
    body:
        'The reading window closed, so the words were destroyed — that is '
        'the promise, not a fault. Only the record that it existed remains.',
    onDismiss: () => Navigator.of(context).pop(),
  );

  /// Already opened before this screen got here — a second device, or a tap on
  /// a stale list.
  Widget _spent() => _Panel(
    key: const ValueKey('spent'),
    fromName: widget.senderName,
    title: 'Already read',
    body:
        'This secret has been opened once, which is all it gets. Nothing is '
        'kept afterwards, so there is nothing left to show.',
    onDismiss: () => Navigator.of(context).pop(),
  );

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
                // Non-null by construction: only [_begin] reaches this stage,
                // and only after the body has arrived.
                _body!,
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
              onPressed: () => _complete(heldFull: false),
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

/// Shared shape for every outcome that is not a reading: the sealed card, a
/// title, an explanation, and a way out.
///
/// One widget rather than three near-copies, because these three differ only
/// in copy and every one of them has to say something true about a secret the
/// reader cannot see.
class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    required this.fromName,
    required this.title,
    required this.body,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String fromName;
  final String title;
  final String body;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 80, 28, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SealedCard(fromName: fromName),
          const SizedBox(height: 26),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTheme.wordmark(
              context,
              24,
            ).copyWith(color: palette.secretPaper),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall!.copyWith(
              height: 1.4,
              color: palette.onScrimFaint,
            ),
          ),
          const SizedBox(height: 24),
          if (actionLabel != null)
            SizedBox(
              width: double.infinity,
              height: 58,
              child: FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.onScrim.withValues(alpha: 0.14),
                  foregroundColor: palette.secretPaper,
                  elevation: 0,
                  shape: const StadiumBorder(),
                  textStyle: AppTheme.bold(theme.textTheme.headlineLarge!),
                ),
                child: Text(actionLabel!),
              ),
            ),
          if (actionLabel != null) const SizedBox(height: 10),
          TextButton(
            onPressed: onDismiss,
            child: Text(
              'Leave it',
              style: theme.textTheme.headlineSmall!.copyWith(
                color: palette.onScrimFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The cream card holding the seal, before the tear.
class _SealedCard extends StatelessWidget {
  const _SealedCard({required this.fromName});

  final String fromName;

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
            '$fromName wrote this for you',
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
    required this.fromName,
    required this.countdown,
    required this.totalSeconds,
  });

  final String fromName;
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
              'FROM ${fromName.toUpperCase()}',
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

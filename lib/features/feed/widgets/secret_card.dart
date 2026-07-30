import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../../../theme/theme_glyphs.dart';
import '../models/feed_item.dart';

/// What the sender sees after sealing a secret, before it is opened.
class SecretSentBubble extends StatelessWidget {
  const SecretSentBubble({super.key, required this.duration});

  final SecretDuration duration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: palette.bubbleMine,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          Glyph('🔒', size: context.glyphs.sentLock),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secret sent',
                  style: theme.textTheme.headlineLarge!.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                Text(
                  duration.shortLabel,
                  style: theme.textTheme.titleLarge!.copyWith(
                    color: palette.onBubbleMineFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// All that is left once a secret has been read — for both people.
class SecretOpenedBubble extends StatelessWidget {
  const SecretOpenedBubble({super.key, required this.openedAt});

  final String openedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          Icon(
            Icons.check,
            size: 19,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Opened',
                  style: theme.textTheme.headlineLarge!.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                Text(
                  'today, $openedAt',
                  style: theme.textTheme.titleLarge!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The sealed card in the thread. Holding it fills the line; when the line is
/// full the reveal takes over the screen.
class SecretCard extends StatefulWidget {
  const SecretCard({super.key, required this.item, this.onOpen});

  final SecretMessage item;

  /// Fired once the hold completes.
  final VoidCallback? onOpen;

  @override
  State<SecretCard> createState() => _SecretCardState();
}

class _SecretCardState extends State<SecretCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _hold.value = 0;
          widget.onOpen?.call();
        }
      });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return GestureDetector(
      onLongPressStart: (_) => _hold.forward(),
      onLongPressEnd: (_) => _hold.reverse(),
      onLongPressCancel: () => _hold.reverse(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        decoration: BoxDecoration(
          color: palette.secretCard,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.bubbleMine,
                shape: BoxShape.circle,
              ),
              child: Glyph('🔒', size: context.glyphs.sealBadge),
            ),
            const SizedBox(height: 18),
            Text(
              'A secret from ${widget.item.sender.name}',
              style: AppTheme.wordmark(context, 21),
            ),
            const SizedBox(height: 8),
            Text(
              'sent ${widget.item.time}',
              style: theme.textTheme.titleLarge!.copyWith(
                color: palette.inkFaint,
              ),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: AnimatedBuilder(
                animation: _hold,
                builder: (context, _) => LinearProgressIndicator(
                  value: _hold.value,
                  minHeight: 3,
                  backgroundColor: theme.colorScheme.outline,
                  valueColor: AlwaysStoppedAnimation(palette.bubbleMine),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'PRESS & HOLD TO OPEN',
              style: theme.textTheme.labelSmall!.copyWith(
                letterSpacing: 1.5,
                color: palette.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

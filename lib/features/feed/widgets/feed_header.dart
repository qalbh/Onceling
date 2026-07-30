import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/tandem_colors.dart';
import '../../../theme/tandem_glyphs.dart';
import '../models/feed_item.dart';

/// Sage circle carrying a person's initial.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.person, this.size = 36});

  final Person person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        shape: BoxShape.circle,
      ),
      child: Text(
        person.initial,
        style: AppTheme.wordmark(
          context,
          size * 0.45,
        ).copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}

/// Thread header: couple name, how long they have been going, streak, viewer.
class FeedHeader extends StatelessWidget {
  const FeedHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.streak,
    required this.viewer,
    this.onOpenSettings,
    this.onSwapViewer,
  });

  final String title;
  final String subtitle;
  final int streak;
  final Person viewer;

  /// Tapping the avatar opens settings.
  final VoidCallback? onOpenSettings;

  /// Demo affordance on long-press: swaps which side of the pair is reading,
  /// so both the sender and recipient layouts are reachable on one device.
  final VoidCallback? onSwapViewer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.wordmark(context, 22)),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium!.copyWith(
                    color: context.tandem.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          _StreakPill(count: streak),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onOpenSettings,
            onLongPress: onSwapViewer,
            child: PersonAvatar(person: viewer),
          ),
        ],
      ),
    );
  }
}

class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: ShapeDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Glyph('🔥', size: context.glyphs.streakFlame),
          Text(
            '$count',
            style: theme.textTheme.labelLarge!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

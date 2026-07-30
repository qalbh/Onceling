import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/theme_glyphs.dart';
import '../models/sample_thread.dart';

/// "Say it back" — the sheet for reacting to a specific message.
class ReactionTray extends StatelessWidget {
  const ReactionTray({super.key, this.title = 'Say it back'});

  final String title;

  /// Resolves to the chosen emoji, or null if dismissed.
  static Future<String?> show(
    BuildContext context, {
    String title = 'Say it back',
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (_) => ReactionTray(title: title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(title, style: AppTheme.wordmark(context, 30)),
            const SizedBox(height: 22),
            GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                for (final emoji in reactionEmoji)
                  _ReactionTile(
                    emoji: emoji,
                    onTap: () => Navigator.of(context).pop(emoji),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactionTile extends StatelessWidget {
  const _ReactionTile({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Glyph(emoji, size: context.glyphs.pickerTile),
      ),
    );
  }
}

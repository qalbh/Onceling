import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/tandem_colors.dart';
import '../../../theme/tandem_glyphs.dart';
import '../../feed/models/feed_item.dart';

/// Shown to the sender the moment their secret is opened.
class SecretOpenedDialog extends StatelessWidget {
  const SecretOpenedDialog({
    super.key,
    required this.reader,
    required this.openedAt,
    required this.heldFullCountdown,
  });

  final Person reader;
  final String openedAt;
  final bool heldFullCountdown;

  static Future<void> show(
    BuildContext context, {
    required Person reader,
    required String openedAt,
    required bool heldFullCountdown,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (_) => SecretOpenedDialog(
        reader: reader,
        openedAt: openedAt,
        heldFullCountdown: heldFullCountdown,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Glyph('🔒', size: context.glyphs.openedSeal),
            ),
            const SizedBox(height: 20),
            Text(
              '${reader.name} read it.',
              style: AppTheme.wordmark(context, 26),
            ),
            const SizedBox(height: 14),
            Text(
              heldFullCountdown
                  ? 'Opened at $openedAt. They held it for the whole countdown.'
                  : 'Opened at $openedAt. They closed it early.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge!.copyWith(
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'IT IS DELETED NOW, FOR BOTH OF YOU',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall!.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
                color: context.tandem.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

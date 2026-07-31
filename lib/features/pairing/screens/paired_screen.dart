import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../../../theme/theme_glyphs.dart';
import '../pairing_celebration.dart';

/// **P2-26** — the moment the pair forms, shown once to both partners.
///
/// Brief §11 calls activation the single most important metric, and this is
/// that instant. Kept deliberately plain: one line of type, one glyph, one way
/// forward. A moment, not a production — it can be dressed up later without
/// touching the gate mechanics underneath it.
///
/// Dismissal goes through [PairingCelebrationNotifier.acknowledge] rather than
/// `context.go`: clearing the celebration is what releases the gate, and
/// navigating by hand would leave the gate wanting this route and bounce back.
class PairedScreen extends ConsumerWidget {
  const PairedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Glyph('🤍', size: context.glyphs.revealSeal),
                const SizedBox(height: 28),
                Text(
                  "You're paired",
                  textAlign: TextAlign.center,
                  style: AppTheme.wordmark(context, 34),
                ),
                const SizedBox(height: 14),
                Text(
                  'This space holds the two of you and no one else.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () => ref
                        .read(pairingCelebrationProvider.notifier)
                        .acknowledge(),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      elevation: 0,
                      shape: const StadiumBorder(),
                      textStyle: AppTheme.bold(theme.textTheme.bodyLarge!),
                    ),
                    child: const Text('Open our space'),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'You can only ever be paired with one person.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium!.copyWith(
                    color: context.palette.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

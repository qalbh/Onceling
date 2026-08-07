import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../../../theme/theme_glyphs.dart';
import '../milestone_copy.dart';
import '../milestone_moment.dart';

/// **P3-03** — the full-screen moment for a crossed milestone.
///
/// The shape of **P2-26**'s paired screen on purpose: one glyph, one line of
/// type, one way forward. A moment, not a production — it can be dressed up
/// later without touching the mechanics underneath.
///
/// Dismissal goes through [MilestoneMomentNotifier.acknowledge] rather than
/// `context.go`, exactly as the paired screen does: clearing the pending
/// milestone is what releases the gate, and navigating by hand would leave the
/// gate wanting this route and bounce straight back.
class MilestoneScreen extends ConsumerWidget {
  const MilestoneScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Zero only in the instant after acknowledge, while the gate is moving.
    final day = ref.watch(milestoneMomentProvider) ?? 0;

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
                Glyph('🌸', size: context.glyphs.revealSeal),
                const SizedBox(height: 28),
                Text(
                  'Day $day',
                  textAlign: TextAlign.center,
                  style: AppTheme.wordmark(context, 44),
                ),
                const SizedBox(height: 14),
                Text(
                  milestoneLine(day),
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
                        .read(milestoneMomentProvider.notifier)
                        .acknowledge(),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      elevation: 0,
                      shape: const StadiumBorder(),
                      textStyle: AppTheme.bold(theme.textTheme.bodyLarge!),
                    ),
                    child: const Text('Back to us'),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Counted from your day one.',
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

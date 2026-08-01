import 'package:flutter/material.dart';

import '../../../theme/theme_colors.dart';
import '../../../theme/theme_glyphs.dart';

/// The thread's three read states (**P2-15**).
///
/// All three replace the *list* only. The header and the compose tray are
/// rendered by [FeedScreen] outside this area and do not depend on `items`, so
/// none of these ever becomes a bare spinner over the whole screen — the app
/// keeps looking like itself while the thread resolves.

/// Waiting on the first snapshot.
///
/// Deliberately quiet: no spinner. The first page usually arrives in well
/// under the time it takes to notice one, and a spinner that flashes reads as
/// something going wrong. Paging back to older messages does not come through
/// here at all — `skipLoadingOnReload` keeps the current thread on screen
/// while the wider window loads.
class FeedLoading extends StatelessWidget {
  const FeedLoading({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// A couple with no messages yet.
///
/// This is the first thing two people see together after pairing, so it gets
/// copy rather than blankness.
class FeedEmpty extends StatelessWidget {
  const FeedEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Glyph('🌱', size: context.glyphs.emptyState),
            const SizedBox(height: 18),
            Text(
              'Nothing here yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              'This is yours and nobody else’s. Say the first thing.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium!.copyWith(
                height: 1.4,
                color: context.palette.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The read failed — a dropped connection, or rules refusing the query.
///
/// Recoverable by design: [onRetry] re-runs the listener rather than asking
/// the reader to restart the app.
class FeedError extends StatelessWidget {
  const FeedError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not load your thread',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              // True rather than reassuring: nothing has been lost, and the
              // most likely cause really is the connection.
              'Nothing has been lost. Check your connection and try again.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium!.copyWith(
                height: 1.4,
                color: context.palette.inkFaint,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

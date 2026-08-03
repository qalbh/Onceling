import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';

/// The brief §10 honesty disclosure (**PI-02**).
///
/// Its own widget because it appears in two places and must be identical in
/// both: once during onboarding, where every new account meets it, and again
/// from settings, where anyone can go back and re-read it. A disclosure nobody
/// can find a second time is weaker than one they can, and two copies of this
/// text would eventually stop matching.
///
/// **The copy is the deliverable here, not the layout.** Three rules it follows:
/// it names the actual defeats rather than abstracting them into "technical
/// limitations"; it states what IS true alongside what is not, because the
/// honesty is stronger for both halves; and it does not apologise, because the
/// limitation is a design choice rather than a failure.
class HonestyDisclosure extends StatelessWidget {
  const HonestyDisclosure({super.key});

  /// Kept as constants so the widget tests assert the shipped words rather
  /// than a paraphrase, and so a rewrite has one place to happen.
  static const title = 'About secrets';

  static const whatIsTrue =
      'A secret can be opened once. The moment it is, the words are deleted — '
      'really deleted, from the server, not hidden behind a flag. Nobody can '
      'read it again. Not them, not you, not us.';

  static const whatIsNotTrue =
      'That does not stop a screenshot. Or a screen recording. Or a second '
      'phone held up to the first. We cannot see any of those, and we are not '
      'going to pretend we can.';

  /// Ends on "trust each other" on purpose. A closing clause followed — "and
  /// it is worth more for being a choice than it would be as a guarantee" —
  /// and was cut: it reached for a conclusion the reader can draw themselves,
  /// and it was the only place the disclosure argued rather than stated.
  static const whyItStillMatters =
      'So a secret here is a ritual, not a lock. It works because the two of '
      'you already trust each other.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    // The longest prose in the app, so it scrolls rather than trusting that it
    // fits. At 200% text scale it does not.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: AppTheme.wordmark(context, 30)),
          const SizedBox(height: 20),
          Text(
            whatIsTrue,
            style: theme.textTheme.headlineMedium!.copyWith(height: 1.45),
          ),
          const SizedBox(height: 18),
          Text(
            whatIsNotTrue,
            style: theme.textTheme.headlineMedium!.copyWith(
              height: 1.45,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            whyItStillMatters,
            style: theme.textTheme.headlineMedium!.copyWith(
              height: 1.45,
              color: palette.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme_colors.dart';
import '../widgets/honesty_disclosure.dart';

/// The §10 disclosure, reachable forever from Settings (**PI-02**).
///
/// **A disclosure nobody can find again is weaker than one they can.** The
/// onboarding pass is the one everybody gets; this is the one they can go back
/// to when it actually matters — the first time someone sends them a secret,
/// or the first time they wonder what "opened once" really bought them.
///
/// Deliberately the same [HonestyDisclosure] widget, not a summary of it. A
/// shorter settings version would be a second wording of the one piece of copy
/// in the app that must not drift.
class HowSecretsWorkScreen extends StatelessWidget {
  const HowSecretsWorkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.feedBackground,
      appBar: AppBar(
        backgroundColor: context.palette.feedBackground,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
          child: const HonestyDisclosure(),
        ),
      ),
    );
  }
}

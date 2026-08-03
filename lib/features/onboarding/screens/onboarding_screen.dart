import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/providers.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../widgets/honesty_disclosure.dart';

/// First run, between sign-up and pairing (**P3-07**, **PI-02**).
///
/// **Two screens, and the second is the point.**
///
/// One to say what the space is, one to be honest about what a secret does and
/// does not do, then out of the way. Three was drafted and cut: the third
/// screen explained that a code pairs you with exactly one person, which is
/// what the pairing screen itself says two taps later — padding in front of the
/// flow brief §11 calls the single most important metric.
///
/// Two screens also means the §10 disclosure is half of onboarding rather than
/// a bullet in a feature list, which is the requirement: the product must say
/// this plainly rather than imply a protection it cannot deliver.
///
/// **Not skippable.** A Skip button on the one screen that exists to be read
/// would defeat the requirement it exists to satisfy — and PI-02 gates external
/// testing precisely because this must not be avoidable. The compensating
/// choice is that it is *short*: two screens, two taps, no dwell timer, no
/// confirmation checkbox, nothing that treats the reader as a liability.
/// It is revisitable forever from Settings → "How secrets work".
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _finishing = false;

  static const _pageCount = 2;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page < _pageCount - 1) {
      await _pages.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    await _finish();
  }

  /// Records that it was seen, then lets the gate move on.
  ///
  /// No navigation here: the profile stream carries `onboardingSeenAt` and the
  /// redirect sees it, exactly as the pairing moment works. Navigating as well
  /// would race the gate.
  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await ref.read(profileServiceProvider).markOnboardingSeen();
    } catch (_) {
      // Failing to record it must not trap someone on the disclosure. They
      // have read it; the worst case is seeing it once more next launch.
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (page) => setState(() => _page = page),
                  children: const [_WhatThisIs(), _SecretsPage()],
                ),
              ),
              const SizedBox(height: 20),
              _Dots(count: _pageCount, active: _page),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: FilledButton(
                  onPressed: _finishing ? null : _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.palette.bubbleMine,
                    foregroundColor: theme.colorScheme.onPrimary,
                    disabledBackgroundColor: context.palette.sageDisabled,
                    disabledForegroundColor: theme.colorScheme.onPrimary,
                    elevation: 0,
                    shape: const StadiumBorder(),
                    textStyle: AppTheme.bold(theme.textTheme.headlineLarge!),
                  ),
                  child: Text(
                    _page < _pageCount - 1 ? 'Next' : 'Find my person',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Page one — what the space is, before anyone is invited into it.
class _WhatThisIs extends StatelessWidget {
  const _WhatThisIs();

  static const title = 'A room for two';

  /// One paragraph, deliberately. A second one followed — "There is no third
  /// person to perform for. That is most of the point." — and was cut: it
  /// hedged, and the idea is already carried by "stays between you".
  static const body =
      'Onceling is one shared space with exactly two people in it. No '
      'audience, no algorithm, nobody else reading over your shoulder. What '
      'you put here stays between you.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: AppTheme.wordmark(context, 30)),
          const SizedBox(height: 20),
          Text(
            body,
            style: theme.textTheme.headlineMedium!.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// Page two — the §10 disclosure, on a screen of its own.
class _SecretsPage extends StatelessWidget {
  const _SecretsPage();

  @override
  Widget build(BuildContext context) => const HonestyDisclosure();
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == active ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == active ? palette.bubbleMine : palette.sageDisabled,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

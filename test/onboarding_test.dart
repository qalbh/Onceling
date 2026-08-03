import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/common/providers.dart';
import 'package:couple_app/features/onboarding/screens/onboarding_screen.dart';
import 'package:couple_app/features/onboarding/widgets/honesty_disclosure.dart';
import 'package:couple_app/features/pairing/screens/pairing_screen.dart';
import 'package:couple_app/main.dart';

import 'test_doubles.dart';

/// **P3-07 / PI-02** — onboarding and the §10 honesty disclosure.
///
/// PI-02 gates external testing, so these are the tests that say the gate is
/// really closed: that a new account cannot reach pairing without passing the
/// disclosure, and that the words themselves are the shipped ones.
void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    required bool onboardingSeen,
    String? coupleId,
    FakeProfileService? profile,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...signedInOverrides(
            coupleId: coupleId,
            onboardingSeen: onboardingSeen,
          ),
          if (profile != null)
            profileServiceProvider.overrideWithValue(profile),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const OncelingApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the gate', () {
    testWidgets('a new account meets onboarding before pairing', (
      tester,
    ) async {
      await pumpApp(tester, onboardingSeen: false);

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(PairingScreen), findsNothing);
    });

    testWidgets('a returning user goes straight through', (tester) async {
      await pumpApp(tester, onboardingSeen: true);

      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(PairingScreen), findsOneWidget);
    });

    testWidgets('an already-paired user who never saw it still does', (
      tester,
    ) async {
      // PI-02 gates external testing, so being early is not a way to skip the
      // disclosure. Onboarding sits ahead of the coupleId branch for this.
      await pumpApp(tester, onboardingSeen: false, coupleId: 'couple-1');

      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('finishing records it, and the gate moves on', (tester) async {
      final profile = FakeProfileService();
      await pumpApp(tester, onboardingSeen: false, profile: profile);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find my person'));
      await tester.pumpAndSettle();

      expect(profile.calls, contains('markOnboardingSeen'));
    });

    testWidgets('it is NOT skippable — there is no way past page two', (
      tester,
    ) async {
      // A Skip button on the one screen that exists to be read would defeat
      // the requirement it exists to satisfy. This fails if one appears.
      await pumpApp(tester, onboardingSeen: false);

      expect(find.text('Skip'), findsNothing);
      expect(find.text('Not now'), findsNothing);
      expect(find.text('Later'), findsNothing);
    });
  });

  group('the disclosure (PI-02)', () {
    testWidgets('is a screen of its own, not a bullet in a list', (
      tester,
    ) async {
      await pumpApp(tester, onboardingSeen: false);

      // Page one first — the disclosure is not on it.
      expect(find.text(HonestyDisclosure.whatIsNotTrue), findsNothing);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text(HonestyDisclosure.title), findsOneWidget);
    });

    testWidgets('names the actual defeats, not "technical limitations"', (
      tester,
    ) async {
      await pumpApp(tester, onboardingSeen: false);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      final text = HonestyDisclosure.whatIsNotTrue.toLowerCase();
      // Brief §10 names these three. Abstracting them is the failure mode.
      expect(text, contains('screenshot'));
      expect(text, contains('screen recording'));
      expect(text, contains('second phone'));
    });

    testWidgets('states what IS true as well as what is not', (tester) async {
      await pumpApp(tester, onboardingSeen: false);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // The honesty is stronger for both halves. P3-01 made these real: the
      // body is hard-deleted and the rule denies even the sender.
      final text = HonestyDisclosure.whatIsTrue.toLowerCase();
      expect(text, contains('deleted'));
      expect(text, contains('once'));
      expect(find.text(HonestyDisclosure.whatIsTrue), findsOneWidget);
    });

    testWidgets('states rather than argues — the cut clause stays cut', (
      tester,
    ) async {
      // Both of these were written, reviewed and removed. They are the kind of
      // edit that gets undone by accident later, so the removal is pinned:
      // page one's second paragraph hedged, and the disclosure's closing
      // clause reached for a conclusion the reader can draw themselves — the
      // only place it argued rather than stated.
      expect(
        HonestyDisclosure.whyItStillMatters,
        endsWith('already trust each other.'),
      );
      expect(
        HonestyDisclosure.whyItStillMatters,
        isNot(contains('worth more')),
      );

      await pumpApp(tester, onboardingSeen: false);
      expect(find.textContaining('most of the point'), findsNothing);
    });

    testWidgets('does not apologise for the limitation', (tester) async {
      // It is a design choice, not a failure. Defensive or apologetic copy
      // would undercut the thing it is trying to establish.
      final all = [
        HonestyDisclosure.whatIsTrue,
        HonestyDisclosure.whatIsNotTrue,
        HonestyDisclosure.whyItStillMatters,
      ].join(' ').toLowerCase();

      for (final word in ['sorry', 'unfortunately', 'apolog', 'regret']) {
        expect(all, isNot(contains(word)), reason: 'apologetic: $word');
      }
    });

    testWidgets('renders at 200% text scale without overflow', (tester) async {
      // The longest prose in the app. It scrolls rather than trusting that it
      // fits, because at this scale it does not.
      await pumpApp(tester, onboardingSeen: false, textScale: 2.0);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(HonestyDisclosure), findsOneWidget);

      // Scrollable, so the tail of the copy is reachable rather than clipped.
      await tester.scrollUntilVisible(
        find.text(HonestyDisclosure.whyItStillMatters),
        200,
        scrollable: find.descendant(
          of: find.byType(HonestyDisclosure),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text(HonestyDisclosure.whyItStillMatters), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

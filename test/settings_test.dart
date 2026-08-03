import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:couple_app/common/app_router.dart';
import 'package:couple_app/features/auth/screens/sign_in_screen.dart';
import 'package:couple_app/features/feed/screens/feed_screen.dart';
import 'package:couple_app/features/onboarding/widgets/honesty_disclosure.dart';
import 'package:couple_app/features/pairing/screens/pairing_screen.dart';
import 'package:couple_app/features/settings/screens/settings_screen.dart';
import 'package:couple_app/features/settings/widgets/unpair_sheet.dart';
import 'package:couple_app/main.dart';

import 'test_doubles.dart';

/// Boots the app signed in and unpaired (the gate parks on pairing, where
/// settings is an allowed overlay), then pushes settings through the router.
Future<void> pumpSettings(
  WidgetTester tester, {
  List<Override>? overrides,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides ?? signedInOverrides(coupleId: 'couple-1'),
      child: const OncelingApp(),
    ),
  );
  await tester.pumpAndSettle();

  // A paired session lands on the feed, an unpaired one on pairing; settings
  // is reachable from either.
  final anchor = find.byType(FeedScreen).evaluate().isNotEmpty
      ? find.byType(FeedScreen)
      : find.byType(PairingScreen);
  GoRouter.of(tester.element(anchor)).push(AppRoutes.settings);
  await tester.pumpAndSettle();
}

/// Settings is a lazy ListView, so rows below the fold do not exist yet.
Future<void> revealRow(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> tapRow(WidgetTester tester, String label) async {
  await revealRow(tester, label);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the pair details and preferences', (tester) async {
    await pumpSettings(
      tester,
      overrides: signedInOverrides(
        coupleId: 'couple-1',
        anniversaryDate: DateTime(2023, 11, 4),
        streakCount: 47,
      ),
    );

    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('paired with Devon'), findsOneWidget);
    expect(find.text('Maya & Devon'), findsOneWidget);
    // Read from the couple since M-10. It used to be a constructor default on
    // SettingsScreen that nothing ever passed.
    expect(find.text('4 November 2023'), findsOneWidget);
    // Read from the couple since M-06. Was a constructor default of 47.
    expect(find.text('47-day'), findsOneWidget);
    await revealRow(tester, 'Tap a slot to swap it.');
    expect(find.text('Tap a slot to swap it.'), findsOneWidget);
  });

  testWidgets('a couple paired before M-10 shows no invented date', (
    tester,
  ) async {
    // No migration by design, so this is every existing couple. The row must
    // read as unset rather than as a date nobody chose — P2-39 makes it
    // editable.
    await pumpSettings(tester);

    expect(find.text('Not set'), findsOneWidget);
    expect(find.text('4 November 2023'), findsNothing);
  });

  testWidgets('the secret-opened alert toggles', (tester) async {
    // Rewritten at PI-01/PI-03. This used to cycle "Mood nudges", which is cut,
    // and sat beside "Screenshot alerts", which is removed. What is left is the
    // one alert the product can actually deliver.
    await pumpSettings(tester);

    await revealRow(tester, 'Tell me when a secret is opened');
    expect(find.text('On'), findsOneWidget);

    await tapRow(tester, 'Tell me when a secret is opened');
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('the removed toggles are gone and stay gone', (tester) async {
    // PI-01: "Screenshot alerts" implied a detection capability the product
    // does not have, and directly contradicted the §10 disclosure.
    // PI-03: "Mood nudges" was not in brief §6 and is exactly the
    // obligation-manufacturing mechanic §12 warns about.
    await pumpSettings(tester);
    await revealRow(tester, 'Tell me when a secret is opened');

    expect(find.text('Screenshot alerts'), findsNothing);
    expect(find.text('Mood nudges'), findsNothing);
  });

  testWidgets('the disclosure is reachable again from settings (PI-02)', (
    tester,
  ) async {
    // A disclosure nobody can find a second time is weaker than one they can.
    await pumpSettings(tester);

    await tapRow(tester, 'How secrets work');

    expect(find.text(HonestyDisclosure.title), findsOneWidget);
    expect(find.text(HonestyDisclosure.whatIsNotTrue), findsOneWidget);
  });

  testWidgets('a favourite slot can be swapped', (tester) async {
    await pumpSettings(tester);

    await tapRow(tester, '🌙');
    expect(find.text('Pick a favourite'), findsOneWidget);

    await tester.tap(find.text('😭'));
    await tester.pumpAndSettle();

    expect(find.text('😭'), findsOneWidget);
    expect(find.text('🌙'), findsNothing);
  });

  testWidgets('unpair requires typing the word exactly', (tester) async {
    await pumpSettings(
      tester,
      overrides: signedInOverrides(coupleId: 'couple-1', streakCount: 47),
    );

    await tapRow(tester, 'Unpair from Devon');

    expect(find.text('Are you sure?'), findsOneWidget);
    // The sheet names what is being destroyed, streak included — real now.
    expect(find.textContaining('47-day streak'), findsOneWidget);

    FilledButton unpairButton() => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Unpair'),
        matching: find.byType(FilledButton),
      ),
    );

    expect(unpairButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'UNPAI');
    await tester.pumpAndSettle();
    expect(unpairButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'unpair'); // upper-cased
    await tester.pumpAndSettle();
    expect(unpairButton().onPressed, isNotNull);
  });

  testWidgets('"Keep us" backs out without unpairing', (tester) async {
    await pumpSettings(tester);

    await tapRow(tester, 'Unpair from Devon');
    await tester.tap(find.text('Keep us'));
    await tester.pumpAndSettle();

    expect(find.text('Are you sure?'), findsNothing);
    // Still on settings, still paired.
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Unpair from Devon'), findsOneWidget);
  });

  testWidgets('confirming unpair calls the callable', (tester) async {
    final pairing = FakePairingService();
    await pumpSettings(
      tester,
      overrides: signedInOverrides(coupleId: 'couple-1', pairing: pairing),
    );

    await tapRow(tester, 'Unpair from Devon');
    await tester.enterText(find.byType(TextField), 'UNPAIR');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unpair'));
    await tester.pumpAndSettle();

    expect(pairing.calls, contains('unpair'));
  });

  testWidgets('a failed unpair keeps the sheet open with its error', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      overrides: signedInOverrides(
        coupleId: 'couple-1',
        pairing: FakePairingService(unpairError: Exception('offline')),
      ),
    );

    await tapRow(tester, 'Unpair from Devon');
    await tester.enterText(find.byType(TextField), 'UNPAIR');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unpair'));
    await tester.pumpAndSettle();

    // Nothing navigated, so the sheet is still the user's context.
    expect(find.byKey(const Key('unpair-error')), findsOneWidget);
    expect(find.byType(UnpairSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirming unpair does not navigate — the gate owns that', (
    tester,
  ) async {
    // Until P2-36 clears `coupleId` server-side there is nothing for the gate
    // to react to, so confirming unpair correctly does nothing visible.
    //
    // This used to call context.go(pairing). Device traces showed the gate
    // overriding it back to /feed on the very next evaluation — coupleId is
    // still set — which unmounted this screen underneath the user. Manual
    // navigation the gate immediately contradicts is the same class of bug as
    // popping a sheet the gate is already disposing.
    await pumpSettings(tester);

    await tapRow(tester, 'Unpair from Devon');
    await tester.enterText(find.byType(TextField), 'UNPAIR');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unpair'));
    await tester.pumpAndSettle();

    // The sheet closes; the screen stays put and nothing is routed.
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(PairingScreen), findsNothing);
    expect(find.byType(SignInScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign out from settings lands on sign-in without throwing', (
    tester,
  ) async {
    final session = FakeSession();
    addTearDown(session.dispose);

    await pumpSettings(tester, overrides: session.overrides());

    await tapRow(tester, 'Sign out');
    await tester.pumpAndSettle();

    // The redirect saw auth flip to null and took the whole app to sign-in.
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

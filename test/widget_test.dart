import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/auth/screens/sign_in_screen.dart';
import 'package:couple_app/features/auth/widgets/email_auth_sheet.dart';
import 'package:couple_app/features/pairing/screens/pairing_screen.dart';
import 'package:couple_app/main.dart';
import 'package:couple_app/theme/app_theme.dart';

import 'test_doubles.dart';

/// Render at phone dimensions — the default 800x600 test surface is too short
/// for these layouts, which pushes the buttons outside the viewport.
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// Boots the real app signed out; the gate lands on sign-in.
Future<void> pumpApp(WidgetTester tester) async {
  usePhoneSurface(tester);
  await tester.pumpWidget(
    ProviderScope(overrides: signedOutOverrides(), child: const OncelingApp()),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cold start signed out lands on sign-in', (tester) async {
    await pumpApp(tester);

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('PRIVATE SPACE'), findsOneWidget);
    expect(find.text('Onceling'), findsOneWidget);
    expect(find.text('Where two become one story.'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Use email or phone'), findsOneWidget);
    expect(find.text('No audience. Just us.'), findsOneWidget);
  });

  testWidgets('"Use email or phone" opens the email sheet', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Use email or phone'));
    await tester.pumpAndSettle();

    expect(find.byType(EmailAuthSheet), findsOneWidget);
    expect(find.byType(PairingScreen), findsNothing);
  });

  testWidgets('cold start signed in and unpaired lands on pairing', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(overrides: signedInOverrides(), child: const OncelingApp()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PairingScreen), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
  });

  group('pairing screen', () {
    // Pumped directly: these tests exercise the screen's own behaviour, not
    // the gate, and none of them taps "Pair us" (which needs a router).
    Future<void> openPairing(WidgetTester tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: signedInOverrides(),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const PairingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows both sections and the user code', (tester) async {
      await openPairing(tester);

      expect(
        find.text('One code, one partner, forever after.'),
        findsOneWidget,
      );
      expect(find.text('YOUR CODE'), findsOneWidget);
      expect(find.text('ENTER THEIRS'), findsOneWidget);
      expect(find.text('Copy code'), findsOneWidget);
      expect(find.text('Share link'), findsOneWidget);
      expect(
        find.text('You can only ever be paired with one person.'),
        findsOneWidget,
      );

      // Each character of the default code renders in its own tile.
      for (final char in 'MK4Q7B'.split('')) {
        expect(find.text(char), findsOneWidget);
      }
    });

    testWidgets('"Pair us" enables only once six characters are entered', (
      tester,
    ) async {
      await openPairing(tester);

      FilledButton pairButton() => tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Pair us'),
          matching: find.byType(FilledButton),
        ),
      );

      expect(pairButton().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'ab12');
      await tester.pump();
      expect(pairButton().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'ab12cd');
      await tester.pump();
      expect(pairButton().onPressed, isNotNull);

      // Input is upper-cased as it is typed.
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('shows the code claimed by the server, not the placeholder', (
      tester,
    ) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: signedInOverrides(pairingCode: 'QW7RTY'),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const PairingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final char in 'QW7RTY'.split('')) {
        expect(find.text(char), findsOneWidget);
      }
      expect(
        find.text('K'),
        findsNothing,
        reason: 'placeholder MK4Q7B is gone',
      );
    });

    testWidgets('claims a code when the profile has none (P2-08)', (
      tester,
    ) async {
      final pairing = FakePairingService();
      usePhoneSurface(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: signedInOverrides(pairingCode: null, pairing: pairing),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const PairingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(pairing.calls, ['ensurePairingCode']);
    });

    testWidgets('does not re-claim when a code already exists', (tester) async {
      final pairing = FakePairingService();
      usePhoneSurface(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: signedInOverrides(pairing: pairing),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const PairingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(pairing.calls, isEmpty);
    });
  });
}

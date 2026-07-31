import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/widgets/email_auth_sheet.dart';
import 'package:couple_app/features/pairing/screens/pairing_screen.dart';
import 'package:couple_app/main.dart';

/// Render at phone dimensions — the default 800x600 test surface is too short
/// for these layouts, which pushes the buttons outside the viewport.
Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  // main() supplies the scope in the real app; tests pump the widget directly.
  await tester.pumpWidget(const ProviderScope(child: OncelingApp()));
}

void main() {
  testWidgets('sign-in screen shows the brand and every auth option', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('PRIVATE SPACE'), findsOneWidget);
    expect(find.text('Onceling'), findsOneWidget);
    expect(find.text('Where two become one story.'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Use email or phone'), findsOneWidget);
    expect(find.text('No audience. Just us.'), findsOneWidget);
  });

  testWidgets('"Use email or phone" opens the email sheet, not pairing', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Use email or phone'));
    await tester.pumpAndSettle();

    expect(find.byType(EmailAuthSheet), findsOneWidget);
    // Auth gating is P2-14; nothing routes anywhere on sign-in.
    expect(find.byType(PairingScreen), findsNothing);
  });

  group('pairing screen', () {
    Future<void> openPairing(WidgetTester tester) async {
      await pumpApp(tester);
      // Apple and Google are disabled until P2-19/P2-20, so route directly.
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed(PairingScreen.routeName);
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
  });
}

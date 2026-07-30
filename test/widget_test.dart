import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/pairing/screens/pairing_screen.dart';
import 'package:couple_app/main.dart';

/// Render at phone dimensions — the default 800x600 test surface is too short
/// for these layouts, which pushes the buttons outside the viewport.
Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const OncelingApp());
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

  for (final label in const [
    'Continue with Apple',
    'Continue with Google',
    'Use email or phone',
  ]) {
    testWidgets('tapping "$label" opens the pairing screen', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      expect(find.byType(PairingScreen), findsNothing);

      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(find.byType(PairingScreen), findsOneWidget);
      expect(find.text('Find your person'), findsOneWidget);
    });
  }

  group('pairing screen', () {
    Future<void> openPairing(WidgetTester tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Continue with Apple'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows both sections and the user code', (tester) async {
      await openPairing(tester);

      expect(find.text('One code, one partner, forever after.'), findsOneWidget);
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

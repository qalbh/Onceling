import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/auth/screens/sign_in_screen.dart';
import 'package:couple_app/features/feed/models/feed_item.dart';
import 'package:couple_app/features/settings/screens/settings_screen.dart';
import 'package:couple_app/main.dart';

Future<void> pumpSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const OncelingApp());

  // Route straight to settings rather than walking the whole flow.
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => const SettingsScreen(viewer: Person.maya),
    ),
  );
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
    await pumpSettings(tester);

    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('paired with Devon'), findsOneWidget);
    expect(find.text('Maya & Devon'), findsOneWidget);
    expect(find.text('4 November 2023'), findsOneWidget);
    expect(find.text('47-day'), findsOneWidget);
    await revealRow(tester, 'Tap a slot to swap it.');
    expect(find.text('Tap a slot to swap it.'), findsOneWidget);
  });

  testWidgets('preference rows cycle through their values', (tester) async {
    await pumpSettings(tester);

    await revealRow(tester, 'Mood nudges');
    expect(find.text('Quiet'), findsOneWidget);

    await tapRow(tester, 'Mood nudges');
    expect(find.text('Loud'), findsOneWidget);

    await tapRow(tester, 'Mood nudges');
    expect(find.text('Off'), findsOneWidget);
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
    await pumpSettings(tester);

    await tapRow(tester, 'Unpair from Devon');

    expect(find.text('Are you sure?'), findsOneWidget);
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

  testWidgets('confirming unpair returns to sign-in with no way back', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tapRow(tester, 'Unpair from Devon');
    await tester.enterText(find.byType(TextField), 'UNPAIR');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unpair'));
    await tester.pumpAndSettle();

    expect(find.text('Onceling'), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    // The whole stack is gone, so there is nothing to pop back to.
    expect(find.byType(SignInScreen), findsOneWidget);
  });
}

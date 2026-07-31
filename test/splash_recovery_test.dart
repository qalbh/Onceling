import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/common/app_router.dart';
import 'package:couple_app/theme/app_theme.dart';

import 'test_doubles.dart';

/// **P2-34** — the splash error state must have a way out.
///
/// Encountered twice during development: signed in, `users/{uid}` absent, and
/// the only control on screen was a retry that refetched a document which did
/// not exist. The user was stuck until they deleted the app.
void main() {
  Widget routedApp(List<Override> overrides) => ProviderScope(
    overrides: overrides,
    child: Consumer(
      builder: (context, ref, _) => MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: ref.watch(routerProvider),
      ),
    ),
  );

  /// Pumps past the splash give-up timer.
  Future<void> reachErrorState(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  }

  testWidgets('a missing profile strands the user on splash', (tester) async {
    final session = FakeSession(profileMissing: true);
    addTearDown(session.dispose);

    await tester.pumpWidget(routedApp(session.overrides()));
    await reachErrorState(tester);

    // The precondition for everything below: the gate holds here.
    expect(find.byKey(const Key('splash-sign-out')), findsOneWidget);
  });

  testWidgets('copy names the real failure, not the connection', (
    tester,
  ) async {
    final session = FakeSession(profileMissing: true);
    addTearDown(session.dispose);

    await tester.pumpWidget(routedApp(session.overrides()));
    await reachErrorState(tester);

    expect(find.textContaining("couldn't finish setting up"), findsOneWidget);
    // "Check your connection" is wrong here and was the old copy.
    expect(find.textContaining('Check your connection'), findsNothing);
  });

  testWidgets('a slow load still blames the connection', (tester) async {
    // Signed out and never resolving: the genuinely-slow case.
    final container = [...signedOutOverrides()];
    await tester.pumpWidget(
      ProviderScope(
        overrides: container,
        child: MaterialApp(theme: AppTheme.light(), home: const SplashScreen()),
      ),
    );
    await reachErrorState(tester);

    expect(find.textContaining('Check your connection'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('sign out from the error state reaches sign-in', (tester) async {
    final session = FakeSession(profileMissing: true);
    addTearDown(session.dispose);

    await tester.pumpWidget(routedApp(session.overrides()));
    await reachErrorState(tester);

    await tester.tap(find.byKey(const Key('splash-sign-out')));
    await tester.pumpAndSettle();

    // The gate resolved signed-out and the user is out of the trap.
    expect(find.text('Onceling'), findsOneWidget);
    expect(find.byKey(const Key('splash-sign-out')), findsNothing);
  });

  testWidgets('setting up the profile again rewrites it and moves on', (
    tester,
  ) async {
    final session = FakeSession(profileMissing: true);
    addTearDown(session.dispose);

    await tester.pumpWidget(routedApp(session.overrides()));
    await reachErrorState(tester);

    expect(find.text('Set up my profile'), findsOneWidget);
    await tester.tap(find.byKey(const Key('splash-primary')));
    await tester.pumpAndSettle();

    expect(session.recoverCalls, 1);
    // Unpaired once the document exists, so the gate lands on pairing.
    expect(find.text('Find your person'), findsOneWidget);
  });

  testWidgets('retry reaches the destination once the document appears', (
    tester,
  ) async {
    final session = FakeSession(profileMissing: true);
    addTearDown(session.dispose);

    await tester.pumpWidget(routedApp(session.overrides(coupleId: 'couple-1')));
    await reachErrorState(tester);
    expect(find.byKey(const Key('splash-sign-out')), findsOneWidget);

    // The write lands out of band — a retry now has something to find.
    session.profileAppears();
    await tester.pumpAndSettle();

    // Already paired, and this session never watched coupleId appear, so the
    // pairing moment stays down and the feed opens directly (P2-26).
    expect(find.byKey(const Key('splash-sign-out')), findsNothing);
    expect(find.text('Find your person'), findsNothing);
  });
}

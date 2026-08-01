import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:couple_app/common/app_router.dart';
import 'package:couple_app/features/feed/models/sample_thread.dart';
import 'package:couple_app/features/feed/screens/feed_screen.dart';
import 'package:couple_app/features/feed/widgets/feed_header.dart';
import 'package:couple_app/features/secret/screens/secret_reveal_screen.dart';
import 'package:couple_app/features/settings/screens/settings_screen.dart';
import 'package:couple_app/theme/app_theme.dart';

import 'test_doubles.dart';

/// [viewerId] is who the test is *signed in as* — the feed has no viewer
/// parameter any more, because the signed-in user is always the viewer.
Future<void> pumpFeed(WidgetTester tester, {String viewerId = devonUid}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  // A minimal router without the auth gate: the feed needs GoRouter in
  // context for the settings push and the secret-reveal route, but these
  // tests exercise the screen, not the redirect.
  final router = GoRouter(
    initialLocation: AppRoutes.feed,
    routes: [
      GoRoute(
        path: AppRoutes.feed,
        // Key by viewer so re-pumping in one test builds fresh state rather
        // than reusing the previous FeedScreen's.
        builder: (_, _) => FeedScreen(key: ValueKey(viewerId)),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.secretReveal,
        pageBuilder: (_, state) {
          final args = state.extra! as SecretRevealArgs;
          return CustomTransitionPage<SecretRevealResult>(
            opaque: false,
            transitionDuration: const Duration(milliseconds: 320),
            child: SecretRevealScreen(
              secret: args.secret,
              senderName: args.senderName,
              body: args.body,
            ),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
          );
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  // Tear the previous tree down first. Re-pumping a ProviderScope with new
  // overrides updates them, but a StreamProvider keeps its existing
  // subscription — so a second pumpFeed in one test would keep the first
  // viewer's identity.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  await tester.pumpWidget(
    ProviderScope(
      // M-02: the feed resolves names through providers now.
      overrides: signedInOverrides(
        uid: viewerId,
        // The mock thread's two people, so a test signed in as Devon is Devon.
        displayName: viewerId == devonUid ? 'Devon' : 'Maya',
        coupleId: 'couple-1',
      ),
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// Holds the sealed card until the reveal takes over the screen.
Future<void> openSecret(WidgetTester tester) async {
  // longPress() releases too early for the fill to complete, so drive it.
  final gesture = await tester.startGesture(
    tester.getCenter(find.text('PRESS & HOLD TO OPEN')),
  );
  await tester.pump(const Duration(milliseconds: 600)); // long-press fires
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150)); // hold fills
  }
  await gesture.up();
  // Single frames only — pumpAndSettle would run the countdown to zero.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400)); // route transition
}

/// Advances past the held-breath and tear stages to the reading.
Future<void> advanceToReading(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1400)); // held breath ends
  await tester.pump(const Duration(milliseconds: 1000)); // tear completes
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('renders the thread header and every message kind', (
    tester,
  ) async {
    await pumpFeed(tester);

    // Title is '<me> & <partner>', and this test is signed in as Devon.
    expect(find.text('Devon & Maya'), findsOneWidget);
    expect(find.text('994 days · since 4 November 2023'), findsOneWidget);
    expect(find.text('47'), findsOneWidget);
    expect(find.text('Exhibit A.'), findsOneWidget);
    expect(find.text('is heads down till four'), findsOneWidget);
    expect(find.text('×14'), findsOneWidget);
  });

  testWidgets('recipient sees the locked secret, sender sees confirmation', (
    tester,
  ) async {
    // Devon received Maya's secret.
    await pumpFeed(tester);
    expect(find.text('A secret from Maya'), findsOneWidget);
    expect(find.text('PRESS & HOLD TO OPEN'), findsOneWidget);
    expect(find.text('Secret sent'), findsNothing);

    // Maya sent it, so she sees the sent bubble instead.
    await pumpFeed(tester, viewerId: mayaUid);
    expect(find.text('Secret sent'), findsOneWidget);
    expect(find.text('they get 30s with it'), findsOneWidget);
    expect(find.text('A secret from Maya'), findsNothing);
  });

  testWidgets('the reveal runs held breath, tear, then reading', (
    tester,
  ) async {
    await pumpFeed(tester);
    await openSecret(tester);

    expect(find.text('FROM MAYA'), findsOneWidget);
    // Both torn halves paint the whole card, so the text exists twice.
    expect(find.text('Maya wrote this for you'), findsNWidgets(2));
    expect(find.text('ONCE IT OPENS, IT IS GONE'), findsOneWidget);

    await advanceToReading(tester);

    expect(
      find.text('I already booked the thing for your birthday. Act surprised.'),
      findsOneWidget,
    );
    expect(find.text('Close now'), findsOneWidget);
  });

  testWidgets('riding the countdown out burns the secret for both', (
    tester,
  ) async {
    await pumpFeed(tester);
    await openSecret(tester);
    await advanceToReading(tester);

    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    // The sender's moment.
    expect(find.text('Devon read it.'), findsOneWidget);
    expect(
      find.text('Opened at 9:31 AM. They held it for the whole countdown.'),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(20, 20)); // dismiss the dialog
    await tester.pumpAndSettle();

    // Only the spent marker survives.
    expect(find.text('Opened'), findsOneWidget);
    expect(find.text('PRESS & HOLD TO OPEN'), findsNothing);
    expect(
      find.text('I already booked the thing for your birthday. Act surprised.'),
      findsNothing,
    );
  });

  testWidgets('closing early is reported differently to the sender', (
    tester,
  ) async {
    await pumpFeed(tester);
    await openSecret(tester);
    await advanceToReading(tester);

    await tester.tap(find.text('Close now'));
    await tester.pumpAndSettle();

    expect(
      find.text('Opened at 9:31 AM. They closed it early.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping a tray emoji appends it to the thread', (tester) async {
    await pumpFeed(tester);

    // The tray is the reader's own favoriteEmojis now, not a per-mock-uid set.
    expect(find.text('🧋'), findsOneWidget); // only in the tray

    await tester.tap(find.text('🧋'));
    await tester.pump();

    // Now in the tray and in the thread.
    expect(find.text('🧋'), findsNWidgets(2));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('composing a message adds it to the thread', (tester) async {
    await pumpFeed(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('Say something'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'be there in ten');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('be there in ten'), findsOneWidget);
  });

  testWidgets('composing as a secret sends a sealed message', (tester) async {
    await pumpFeed(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'the surprise is a dog');
    await tester.tap(find.text('Secret'));
    await tester.pumpAndSettle();

    expect(find.text('A secret'), findsOneWidget);
    expect(find.text('They can read it for'), findsOneWidget);

    await tester.ensureVisible(find.text('10 seconds'));
    await tester.tap(find.text('10 seconds'));
    await tester.pumpAndSettle();

    // The sheet scrolls in secret mode, so bring the button into view first.
    await tester.ensureVisible(find.text('Seal & send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seal & send'));
    await tester.pumpAndSettle();

    // Devon sent it, so he sees the confirmation form.
    expect(find.text('Secret sent'), findsOneWidget);
    expect(find.text('they get 10s with it'), findsOneWidget);
  });

  testWidgets('long-pressing a message applies a reaction', (tester) async {
    await pumpFeed(tester);

    await tester.longPress(find.text('Exhibit A.'));
    await tester.pumpAndSettle();
    expect(find.text('Say it back'), findsOneWidget);

    await tester.tap(find.text('😮'));
    await tester.pumpAndSettle();

    expect(find.text('😮'), findsOneWidget); // now a reaction chip
  });

  testWidgets('renders as the signed-in user, whoever that is', (tester) async {
    // Signed in as the recipient: the secret is locked.
    await pumpFeed(tester, viewerId: devonUid);
    expect(find.text('A secret from Maya'), findsOneWidget);
    expect(find.text('Secret sent'), findsNothing);

    // Signed in as the sender: the same thread mirrors, with no gesture.
    await pumpFeed(tester, viewerId: mayaUid);
    expect(find.text('Secret sent'), findsOneWidget);
    expect(find.text('A secret from Maya'), findsNothing);
  });

  testWidgets('long-pressing the header avatar changes no identity', (
    tester,
  ) async {
    // The swap was a Phase 1 dev affordance from before auth existed. It let a
    // real user become their partner, so it is gone. This fails if it returns.
    await pumpFeed(tester, viewerId: devonUid);
    expect(find.text('A secret from Maya'), findsOneWidget);

    await tester.longPress(
      find.descendant(
        of: find.byType(FeedHeader),
        matching: find.byType(PersonAvatar),
      ),
    );
    await tester.pumpAndSettle();

    // With no long-press recognizer left, the gesture falls through to the tap
    // and opens settings — the ordinary behaviour, and not an identity change.
    if (find.byType(SettingsScreen).evaluate().isNotEmpty) {
      GoRouter.of(tester.element(find.byType(SettingsScreen))).pop();
      await tester.pumpAndSettle();
    }

    // Back on the thread, still the recipient's view: nothing mirrored.
    expect(find.text('A secret from Maya'), findsOneWidget);
    expect(find.text('Secret sent'), findsNothing);
  });

  test('the header exposes no viewer-swap hook at all', () {
    // Structural: a behavioural test cannot prove the callback is absent, and
    // re-adding the parameter is how the affordance would come back.
    final source = File(
      'lib/features/feed/widgets/feed_header.dart',
    ).readAsStringSync();
    expect(source.contains('onSwapViewer'), isFalse);
  });

  testWidgets('tapping the avatar opens settings', (tester) async {
    await pumpFeed(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(FeedHeader),
        matching: find.byType(PersonAvatar),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    // Settings shows the same signed-in identity the feed does — since M-02
    // neither takes a viewer, both read it from the profile.
    // Signed in as Devon, so the partner is Maya.
    expect(find.text('paired with Maya'), findsOneWidget);
    expect(find.text('Couple name'), findsOneWidget);

    // The rest of the page is below the fold in a lazy list.
    await tester.scrollUntilVisible(
      find.text('Unpair from Maya'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Unpair from Maya'), findsOneWidget);
  });

  testWidgets('setting a mood updates the status line', (tester) async {
    await pumpFeed(tester);

    await tester.tap(find.text('is heads down till four'));
    await tester.pumpAndSettle();
    expect(find.text('How are you, really?'), findsOneWidget);

    await tester.tap(find.text('☕'));
    await tester.enterText(find.byType(TextField), 'running on one coffee');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Set my mood'));
    await tester.tap(find.text('Set my mood'));
    await tester.pumpAndSettle();

    expect(find.text('running on one coffee'), findsOneWidget);
    expect(find.text('is heads down till four'), findsNothing);
  });
}

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/common/app_router.dart';
import 'package:couple_app/common/providers.dart';
import 'package:couple_app/features/auth/models/user_profile.dart';
import 'package:couple_app/features/feed/models/feed_item.dart';
import 'package:couple_app/features/feed/widgets/feed_header.dart';
import 'package:couple_app/features/feed/widgets/feed_item_view.dart';
import 'package:couple_app/features/milestone/milestone_copy.dart';
import 'package:couple_app/features/milestone/milestone_moment.dart';
import 'package:couple_app/features/milestone/screens/milestone_screen.dart';
import 'package:couple_app/features/pairing/couple_names.dart';
import 'package:couple_app/features/pairing/models/couple.dart';
import 'package:couple_app/theme/app_theme.dart';

/// **P3-03** — the full-screen moment: once per partner, never on a later
/// cold start.
///
/// The provider compares two pieces of durable server state —
/// `couples.milestoneCelebrated` against the partner's own
/// `users/{uid}.milestoneSeen` — so every test here is really a test of that
/// comparison surviving the situations P2-26 taught us about: cold starts,
/// rebuilds, and the partner who did nothing.
UserProfile profile(String uid, {int milestoneSeen = 0}) => UserProfile(
  uid: uid,
  displayName: 'Maya',
  favoriteEmojis: const [],
  coupleId: 'c1',
  milestoneSeen: milestoneSeen,
);

Couple couple({int milestoneCelebrated = 0}) => Couple(
  id: 'c1',
  memberIds: const ['a', 'b'],
  memberNames: const {'a': 'Maya', 'b': 'Sam'},
  milestoneCelebrated: milestoneCelebrated,
);

ProviderContainer harness({
  required UserProfile? me,
  required Couple? us,
  FakeFirebaseFirestore? db,
}) {
  final container = ProviderContainer(
    overrides: [
      firestoreProvider.overrideWithValue(db ?? FakeFirebaseFirestore()),
      currentUserProvider.overrideWith((ref) => Stream.value(me)),
      coupleProvider.overrideWith((ref) => Stream.value(us)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Streams need a beat to emit into the providers.
Future<void> settle(ProviderContainer container) async {
  await container.read(currentUserProvider.future);
  await container.read(coupleProvider.future);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('when the moment is owed', () {
    test('celebrated above seen → the moment is pending', () async {
      final container = harness(
        me: profile('a'),
        us: couple(milestoneCelebrated: 100),
      );
      await settle(container);
      expect(container.read(milestoneMomentProvider), 100);
    });

    test('a cold start AFTER seeing it shows nothing', () async {
      // The requirement stated exactly: seen == celebrated is durable server
      // state, so a fresh session compares equal and never replays.
      final container = harness(
        me: profile('a', milestoneSeen: 100),
        us: couple(milestoneCelebrated: 100),
      );
      await settle(container);
      expect(container.read(milestoneMomentProvider), isNull);
    });

    test('no couple, or no milestone yet → nothing', () async {
      final none = harness(me: profile('a'), us: couple());
      await settle(none);
      expect(none.read(milestoneMomentProvider), isNull);

      final unpaired = harness(me: profile('a'), us: null);
      await settle(unpaired);
      expect(unpaired.read(milestoneMomentProvider), isNull);
    });

    test('each partner sees it independently — one seen, one owed', () async {
      // The couple document is shared; the seen-marker is not. Partner A
      // dismissed it, partner B has not opened the app yet.
      final a = harness(
        me: profile('a', milestoneSeen: 100),
        us: couple(milestoneCelebrated: 100),
      );
      final b = harness(me: profile('b'), us: couple(milestoneCelebrated: 100));
      await settle(a);
      await settle(b);
      expect(a.read(milestoneMomentProvider), isNull);
      expect(b.read(milestoneMomentProvider), 100);
    });

    test('a leap across two milestones shows the highest once', () async {
      // Dormant app: 365 and 500 both fired server-side since last open. The
      // moment shown is the one that is true today; the feed scrollback holds
      // the record of both.
      final container = harness(
        me: profile('a', milestoneSeen: 100),
        us: couple(milestoneCelebrated: 500),
      );
      await settle(container);
      expect(container.read(milestoneMomentProvider), 500);
    });
  });

  group('acknowledge', () {
    test('clears the moment and makes the seen-marker durable', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('a').set({'milestoneSeen': 0});
      final container = harness(
        me: profile('a'),
        us: couple(milestoneCelebrated: 100),
        db: db,
      );
      await settle(container);
      expect(container.read(milestoneMomentProvider), 100);

      container.read(milestoneMomentProvider.notifier).acknowledge();
      await Future<void>.delayed(Duration.zero);

      // Gone locally, at once — the gate must release without waiting for
      // the write's round trip.
      expect(container.read(milestoneMomentProvider), isNull);

      // And durable: this is what the next cold start compares against.
      final written = await db.collection('users').doc('a').get();
      expect(written.data()?['milestoneSeen'], 100);
    });

    test('stays cleared while the profile stream is stale', () async {
      // Between the tap and the profile stream echoing the new value, the
      // provider recomputes from OLD data. The session guard is what stops
      // the moment flashing back in that window.
      final container = harness(
        me: profile('a'), // milestoneSeen stays 0 — the echo never arrives
        us: couple(milestoneCelebrated: 100),
      );
      await settle(container);
      container.read(milestoneMomentProvider.notifier).acknowledge();
      await Future<void>.delayed(Duration.zero);

      container.invalidate(milestoneMomentProvider);
      await settle(container);
      expect(container.read(milestoneMomentProvider), isNull);
    });
  });

  group('the gate', () {
    String? redirect({
      bool milestonePending = false,
      bool justPaired = false,
      String at = AppRoutes.feed,
    }) => resolveRedirect(
      isLoadingAuth: false,
      isSignedIn: true,
      isLoadingProfile: false,
      profileExists: true,
      coupleId: 'c1',
      currentLocation: at,
      justPaired: justPaired,
      milestonePending: milestonePending,
    );

    test('a pending milestone pulls the open into the moment', () {
      expect(redirect(milestonePending: true), AppRoutes.milestone);
    });

    test('standing on the moment stays put', () {
      expect(redirect(milestonePending: true, at: AppRoutes.milestone), isNull);
    });

    test('acknowledged → the gate wants the feed again', () {
      expect(redirect(at: AppRoutes.milestone), AppRoutes.feed);
    });

    test('the pairing moment outranks it', () {
      // Cannot co-occur today (a couple paired today is on day zero), but if
      // P2-39's backdating ever makes it possible, activation wins.
      expect(
        redirect(milestonePending: true, justPaired: true),
        AppRoutes.paired,
      );
    });
  });

  group('the screens', () {
    testWidgets('the moment shows the day, the line, and dismisses', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('a').set({'milestoneSeen': 0});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreProvider.overrideWithValue(db),
            currentUserProvider.overrideWith(
              (ref) => Stream.value(profile('a')),
            ),
            coupleProvider.overrideWith(
              (ref) => Stream.value(couple(milestoneCelebrated: 365)),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const MilestoneScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Day 365'), findsOneWidget);
      expect(find.text(milestoneLine(365)), findsOneWidget);

      await tester.tap(find.text('Back to us'));
      await tester.pumpAndSettle();

      final written = await db.collection('users').doc('a').get();
      expect(written.data()?['milestoneSeen'], 365);
    });

    testWidgets('the feed renders a milestone centred, owned by nobody', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: FeedItemView(
                item: MilestoneMessage(
                  id: 'm1',
                  createdAt: DateTime(2026, 8, 7),
                  day: 100,
                ),
                viewerId: 'a',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Day 100'), findsOneWidget);
      expect(find.text(milestoneLine(100)), findsOneWidget);
      // No avatar chip: an authored item carries one, and this must not.
      expect(find.byType(PersonAvatar), findsNothing);
    });
  });

  group('the copy', () {
    test('every milestone has its own line, and a future one degrades', () {
      final lines = milestoneDays.map(milestoneLine).toSet();
      expect(lines.length, milestoneDays.length, reason: 'no reuse');
      for (final line in lines) {
        expect(line.contains('!'), isFalse, reason: 'nothing shouted');
      }
      expect(milestoneLine(2000), contains('2000'));
    });
  });
}

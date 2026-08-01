import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:couple_app/common/app_router.dart';
import 'package:couple_app/common/providers.dart';
import 'package:couple_app/features/feed/feed_providers.dart';
import 'package:couple_app/features/feed/screens/feed_screen.dart';
import 'package:couple_app/features/feed/widgets/emoji_tray.dart';
import 'package:couple_app/features/feed/widgets/feed_header.dart';
import 'package:couple_app/features/feed/widgets/feed_states.dart';
import 'package:couple_app/features/secret/screens/secret_reveal_screen.dart';
import 'package:couple_app/features/settings/screens/settings_screen.dart';
import 'package:couple_app/theme/app_theme.dart';

import 'test_doubles.dart';

/// The two people in these tests. Real uids in shape — the mock `mayaUid` and
/// `devonUid` constants went with `sample_thread.dart` at **P2-12**.
const me = 'uid-test';
const them = 'uid-partner';
const ourCouple = 'couple-1';

/// Builds the feed over [db], signed in as [viewerId].
///
/// Only `firestoreProvider` is faked, so the query, the mapper, the pagination
/// window and every write run for real against an in-memory backend.
Future<ProviderContainer> pumpFeed(
  WidgetTester tester, {
  required FakeFirebaseFirestore db,
  String viewerId = me,
  String displayName = 'Maya',
  List<Override> extra = const [],
  FakeMoodService? mood,
}) async {
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
      overrides: [
        ...signedInOverrides(
          uid: viewerId,
          displayName: displayName,
          partnerUid: viewerId == me ? them : me,
          coupleId: ourCouple,
          firestore: db,
          mood: mood ?? FakeMoodService(),
        ),
        ...extra,
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  return ProviderScope.containerOf(tester.element(find.byType(FeedScreen)));
}

/// Every `items` document currently in [db], newest first.
Future<List<Map<String, dynamic>>> itemsIn(FakeFirebaseFirestore db) async {
  final snap = await db.collection('items').get();
  return snap.docs.map((d) => d.data()).toList();
}

void main() {
  group('reading the thread', () {
    testWidgets('renders the couple\'s items and not another couple\'s', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await seedItem(
        db,
        coupleId: ourCouple,
        senderId: them,
        body: 'thought of you immediately.',
        secondsAgo: 60,
      );
      await seedItem(
        db,
        coupleId: ourCouple,
        senderId: me,
        body: 'gooseee.',
        secondsAgo: 30,
      );
      // A different couple's thread, in the same collection. The query's
      // coupleId filter is what keeps it out — Security Rules enforce the same
      // scoping server-side, and `rules-tests/items_rules.test.mjs` proves
      // that half. This test proves the client asks the right question.
      await seedItem(
        db,
        coupleId: 'couple-elsewhere',
        senderId: 'uid-stranger',
        body: 'not for you',
      );

      await pumpFeed(tester, db: db);

      expect(find.text('thought of you immediately.'), findsOneWidget);
      expect(find.text('gooseee.'), findsOneWidget);
      expect(find.text('not for you'), findsNothing);
    });

    testWidgets('a message arriving later appears without a refresh', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await seedItem(
        db,
        coupleId: ourCouple,
        senderId: me,
        body: 'first',
        secondsAgo: 60,
      );
      await pumpFeed(tester, db: db);
      expect(find.text('and then this'), findsNothing);

      // The partner writes. Nothing on this device asked for it.
      await seedItem(
        db,
        coupleId: ourCouple,
        senderId: them,
        body: 'and then this',
      );
      await tester.pumpAndSettle();

      expect(find.text('and then this'), findsOneWidget);
    });

    testWidgets('renders as the signed-in user, whoever that is', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await seedItem(
        db,
        coupleId: ourCouple,
        senderId: them,
        type: 'secret',
        extra: {
          'secretState': 'sealed',
          'revealDurationSeconds': 30,
          'heldFullCountdown': false,
        },
      );

      // The recipient sees a locked card.
      await pumpFeed(tester, db: db);
      expect(find.text('A secret from Devon'), findsOneWidget);
      expect(find.text('PRESS & HOLD TO OPEN'), findsOneWidget);
      expect(find.text('Secret sent'), findsNothing);

      // The sender sees the confirmation instead — same document, mirrored.
      await pumpFeed(tester, db: db, viewerId: them, displayName: 'Devon');
      expect(find.text('Secret sent'), findsOneWidget);
      expect(find.text('they get 30s with it'), findsOneWidget);
      expect(find.text('A secret from Devon'), findsNothing);
    });

    testWidgets('long-pressing the header avatar changes no identity', (
      tester,
    ) async {
      // The swap was a Phase 1 dev affordance from before auth existed. It let
      // a real user become their partner, so it is gone. This fails if it
      // returns.
      final db = FakeFirebaseFirestore();
      await seedItem(
        db,
        coupleId: ourCouple,
        senderId: them,
        body: 'from them',
      );
      await pumpFeed(tester, db: db);

      await tester.longPress(
        find.descendant(
          of: find.byType(FeedHeader),
          matching: find.byType(PersonAvatar),
        ),
      );
      await tester.pumpAndSettle();

      // With no long-press recognizer left, the gesture falls through to the
      // tap and opens settings — ordinary behaviour, not an identity change.
      if (find.byType(SettingsScreen).evaluate().isNotEmpty) {
        GoRouter.of(tester.element(find.byType(SettingsScreen))).pop();
        await tester.pumpAndSettle();
      }

      expect(find.text('from them'), findsOneWidget);
    });

    test('the header exposes no viewer-swap hook at all', () {
      // Structural: a behavioural test cannot prove the callback is absent,
      // and re-adding the parameter is how the affordance would come back.
      final source = File(
        'lib/features/feed/widgets/feed_header.dart',
      ).readAsStringSync();
      expect(source.contains('onSwapViewer'), isFalse);
    });
  });

  group('P2-15 — the three states', () {
    testWidgets('loading leaves the header and the tray on screen', (
      tester,
    ) async {
      await pumpFeed(
        tester,
        db: FakeFirebaseFirestore(),
        // A stream that never emits: the feed stays in AsyncLoading.
        extra: [
          feedProvider.overrideWith((ref) => const Stream<FeedPage>.empty()),
        ],
      );

      expect(find.byType(FeedLoading), findsOneWidget);
      // The point of P2-15: not a bare spinner over the whole screen. The
      // parts that do not depend on `items` keep rendering.
      expect(find.byType(FeedHeader), findsOneWidget);
      expect(find.byType(EmojiTray), findsOneWidget);
    });

    testWidgets('a newly paired couple gets copy, not blankness', (
      tester,
    ) async {
      await pumpFeed(tester, db: FakeFirebaseFirestore());

      expect(find.byType(FeedEmpty), findsOneWidget);
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(
        find.text('This is yours and nobody else’s. Say the first thing.'),
        findsOneWidget,
      );
      expect(find.byType(EmojiTray), findsOneWidget);
    });

    testWidgets('an error says something true and offers a retry', (
      tester,
    ) async {
      var attempts = 0;
      final container = await pumpFeed(
        tester,
        db: FakeFirebaseFirestore(),
        extra: [
          feedProvider.overrideWith((ref) {
            attempts++;
            // Fails once, then succeeds — so the retry has something to prove.
            if (attempts == 1) {
              return Stream<FeedPage>.error(
                FirebaseException(plugin: 'cloud_firestore', code: 'unknown'),
              );
            }
            return Stream.value(const FeedPage(items: [], hasMore: false));
          }),
        ],
      );

      expect(find.byType(FeedError), findsOneWidget);
      expect(find.text('Could not load your thread'), findsOneWidget);
      expect(
        find.text(
          'Nothing has been lost. Check your connection and try again.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(attempts, 2, reason: 'the retry re-ran the query');
      expect(find.byType(FeedError), findsNothing);
      expect(find.byType(FeedEmpty), findsOneWidget);
      container.dispose();
    });
  });

  group('writing', () {
    testWidgets('composing writes a text item scoped to the couple', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await pumpFeed(tester, db: db);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('Say something'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'be there in ten');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      final written = await itemsIn(db);
      expect(written, hasLength(1));
      expect(written.single['type'], 'text');
      expect(written.single['body'], 'be there in ten');
      expect(written.single['coupleId'], ourCouple);
      expect(written.single['senderId'], me);
      expect(written.single['reactions'], isEmpty);
      expect(written.single['createdAt'], isA<Timestamp>());

      // And it came back through the listener, not from local state.
      expect(find.text('be there in ten'), findsOneWidget);
    });

    testWidgets('a tray tap writes an emoji item', (tester) async {
      final db = FakeFirebaseFirestore();
      await pumpFeed(tester, db: db);

      await tester.tap(find.text('🧋'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final written = await itemsIn(db);
      expect(written, hasLength(1));
      expect(written.single['type'], 'emoji');
      expect(written.single['emoji'], '🧋');
      expect(written.single['coupleId'], ourCouple);
      expect(written.single['senderId'], me);
      // One tap, one item: the mock's `count: 14` aggregation is not
      // reachable from a client, because `allow update` is reactions-only.
      expect(written.single['count'], 1);
    });

    testWidgets('a secret writes the item and its body in one go', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await pumpFeed(tester, db: db);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'the surprise is a dog');
      await tester.tap(find.text('Secret'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('10 seconds'));
      await tester.tap(find.text('10 seconds'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Seal & send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seal & send'));
      await tester.pumpAndSettle();

      final items = await db.collection('items').get();
      final bodies = await db.collection('secretBodies').get();
      expect(items.docs, hasLength(1));
      expect(bodies.docs, hasLength(1));

      final item = items.docs.single;
      expect(item.data()['type'], 'secret');
      expect(item.data()['secretState'], 'sealed');
      expect(item.data()['revealDurationSeconds'], 10);
      // P3-01 owns this field, and it is not in the rules' permitted create
      // key set — writing it as an explicit null would be rejected.
      expect(item.data().containsKey('openingStartedAt'), isFalse);

      // Keyed by item id, and carrying all three load-bearing fields.
      final body = bodies.docs.single;
      expect(body.id, item.id, reason: 'bodies are keyed by their item');
      expect(body.data()['coupleId'], ourCouple, reason: 'P2-36 sweeps by it');
      expect(body.data()['senderId'], me, reason: 'rules bind create to it');
      expect(body.data()['body'], 'the surprise is a dog');

      // The sender's own view of it.
      expect(find.text('Secret sent'), findsOneWidget);
      expect(find.text('they get 10s with it'), findsOneWidget);
    });

    testWidgets(
      'an until-closed secret omits the duration rather than nulling it',
      (tester) async {
        final db = FakeFirebaseFirestore();
        await pumpFeed(tester, db: db);

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'no clock on this one');
        await tester.tap(find.text('Secret'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('until they close it'));
        await tester.tap(find.text('until they close it'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Seal & send'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Seal & send'));
        await tester.pumpAndSettle();

        final item = (await db.collection('items').get()).docs.single;
        // `keys().hasOnly(itemKeysFor(type))` counts an explicit null as a
        // present key, so a nulled duration would still have to be permitted.
        expect(item.data().containsKey('revealDurationSeconds'), isFalse);
      },
    );

    testWidgets('long-pressing a message writes only your own reaction', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      final id = await seedItem(
        db,
        coupleId: ourCouple,
        senderId: them,
        body: 'Exhibit A.',
        // The partner already reacted. Ours must join theirs, not replace it.
        reactions: {them: '🥹'},
      );
      await pumpFeed(tester, db: db);

      await tester.longPress(find.text('Exhibit A.'));
      await tester.pumpAndSettle();
      expect(find.text('Say it back'), findsOneWidget);

      await tester.tap(find.text('😮'));
      await tester.pumpAndSettle();

      final stored = (await db.doc('items/$id').get()).data()!;
      expect(stored['reactions'], {them: '🥹', me: '😮'});
      expect(find.text('😮'), findsOneWidget);
    });

    testWidgets('setting a mood goes through the callable, not a write', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      final mood = FakeMoodService();
      await seedItem(
        db,
        coupleId: ourCouple,
        senderId: them,
        type: 'status',
        body: 'is heads down till four',
        emoji: '🎧',
      );
      await pumpFeed(tester, db: db, mood: mood);

      await tester.tap(find.text('is heads down till four'));
      await tester.pumpAndSettle();
      expect(find.text('How are you, really?'), findsOneWidget);

      await tester.tap(find.text('☕'));
      await tester.enterText(find.byType(TextField), 'running on one coffee');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Set my mood'));
      await tester.tap(find.text('Set my mood'));
      await tester.pumpAndSettle();

      // The ambient half lands on `couples`, which denies every client write,
      // so both halves are the callable's job. Nothing was written here.
      expect(mood.calls, [(emoji: '☕', note: 'running on one coffee')]);
      expect(await itemsIn(db), hasLength(1), reason: 'no client-side write');
    });

    testWidgets('a failed send says so rather than silently doing nothing', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      final mood = FakeMoodService(
        error: FirebaseException(plugin: 'cloud_functions', code: 'internal'),
      );
      await seedItem(
        db,
        coupleId: ourCouple,
        senderId: them,
        type: 'status',
        body: 'is heads down till four',
        emoji: '🎧',
      );
      await pumpFeed(tester, db: db, mood: mood);

      await tester.tap(find.text('is heads down till four'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('😌'));
      await tester.ensureVisible(find.text('Set my mood'));
      await tester.tap(find.text('Set my mood'));
      await tester.pumpAndSettle();

      expect(find.text('That did not send. Try again.'), findsOneWidget);
    });
  });

  group('secrets stay sealed until P3-01', () {
    testWidgets('holding to open admits it cannot open yet', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedItem(
        db,
        coupleId: ourCouple,
        senderId: them,
        type: 'secret',
        extra: {
          'secretState': 'sealed',
          'revealDurationSeconds': 30,
          'heldFullCountdown': false,
        },
      );
      await pumpFeed(tester, db: db);

      // longPress() releases too early for the fill to complete, so drive it.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('PRESS & HOLD TO OPEN')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // No body was fetched, because none is readable: `secretBodies` grants
      // `get` only while the item is `opening`, and nothing moves it there.
      expect(find.text('Not yet'), findsOneWidget);
      expect(find.text('Leave it sealed'), findsOneWidget);

      await tester.tap(find.text('Leave it sealed'));
      await tester.pumpAndSettle();

      // Still sealed afterwards. Nothing was consumed.
      expect(find.text('PRESS & HOLD TO OPEN'), findsOneWidget);
    });
  });

  group('pagination', () {
    test('a second page loads and does not duplicate the first', () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < feedPageSize + 15; i++) {
        await seedItem(
          db,
          coupleId: ourCouple,
          senderId: i.isEven ? me : them,
          body: 'message $i',
          secondsAgo: i,
        );
      }

      final container = ProviderContainer(
        overrides: signedInOverrides(coupleId: ourCouple, firestore: db),
      );
      addTearDown(container.dispose);

      // Let the profile land first. `feedProvider` watches it, so reading the
      // feed before the coupleId arrives builds the unpaired branch and then
      // immediately rebuilds — and the first future is discarded mid-flight.
      await container.read(currentUserProvider.future);
      final first = await container.read(feedProvider.future);
      expect(first.items, hasLength(feedPageSize));
      expect(first.hasMore, isTrue);
      // Newest first, which is the order a reversed list wants.
      expect((first.items.first as dynamic).text, 'message 0');

      container.read(feedWindowProvider.notifier).loadMore();
      final second = await container.read(feedProvider.future);

      expect(second.items, hasLength(feedPageSize + 15));
      expect(second.hasMore, isFalse, reason: 'the window outran the thread');
      expect(
        second.items.map((i) => i.id).toSet(),
        hasLength(feedPageSize + 15),
        reason: 'no id appears twice across the two pages',
      );
    });

    test('an unpaired user queries nothing at all', () async {
      final db = FakeFirebaseFirestore();
      await seedItem(
        db,
        coupleId: ourCouple,
        senderId: them,
        body: 'not theirs to see',
      );

      // The router gate keeps this state off the feed, but the provider does
      // not assume the gate: with no coupleId there is no scoped query to run,
      // so it must not run an unscoped one.
      final container = ProviderContainer(
        overrides: signedInOverrides(firestore: db),
      );
      addTearDown(container.dispose);

      await container.read(currentUserProvider.future);
      final page = await container.read(feedProvider.future);
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    testWidgets('scrolling to the old end grows the window', (tester) async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < feedPageSize + 5; i++) {
        await seedItem(
          db,
          coupleId: ourCouple,
          senderId: them,
          body: 'message $i',
          secondsAgo: i,
        );
      }
      final container = await pumpFeed(tester, db: db);
      expect(container.read(feedWindowProvider), feedPageSize);

      // The list is reverse: true, so dragging the content *down* walks back
      // through older messages towards maxScrollExtent.
      for (var i = 0; i < 12; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, 600));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(container.read(feedWindowProvider), feedPageSize * 2);
      expect(find.text('message ${feedPageSize + 4}'), findsOneWidget);
    });
  });

  testWidgets('tapping the avatar opens settings', (tester) async {
    final db = FakeFirebaseFirestore();
    await pumpFeed(tester, db: db);

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
    expect(find.text('paired with Devon'), findsOneWidget);
    expect(find.text('Couple name'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Unpair from Devon'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Unpair from Devon'), findsOneWidget);
  });
}

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/common/app_router.dart';
import 'package:couple_app/common/providers.dart';
import 'package:couple_app/features/pairing/models/pairing_request.dart';
import 'package:couple_app/features/pairing/pairing_celebration.dart';
import 'package:couple_app/features/pairing/pairing_errors.dart';
import 'package:couple_app/features/pairing/screens/pairing_screen.dart';
import 'package:couple_app/theme/app_theme.dart';

import 'test_doubles.dart';

/// A pairing screen inside a real MaterialApp, so sheets and buttons behave.
Widget _pairingApp(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(theme: AppTheme.light(), home: const PairingScreen()),
);

FirebaseFunctionsException _rejection(String reason) =>
    FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'rejected',
      details: {'reason': reason},
    );

void main() {
  // The pairing screen is content-heavy; give it a tall viewport so a genuine
  // overflow still fails rather than being masked by the default 800x600.
  void useTallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 3200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  group('P2-23 — send confirmation', () {
    testWidgets('echoes the code back and reveals nothing about its owner', (
      tester,
    ) async {
      useTallView(tester);
      await tester.pumpWidget(_pairingApp(signedInOverrides()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'ABC123');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pair us'));
      await tester.pumpAndSettle();

      expect(find.text('Send a pairing request?'), findsOneWidget);
      // Spaced echo, so a transposed character is visible.
      expect(find.text('A B C 1 2 3'), findsOneWidget);

      // The whole point of P2-23: no identity leaks before acceptance.
      expect(find.textContaining('Maya'), findsNothing);
      expect(find.textContaining('Devon'), findsNothing);
    });

    testWidgets('Cancel closes without sending', (tester) async {
      useTallView(tester);
      final pairing = FakePairingService();
      await tester.pumpWidget(_pairingApp(signedInOverrides(pairing: pairing)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'ABC123');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pair us'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Send a pairing request?'), findsNothing);
      expect(pairing.calls, isEmpty);
    });

    testWidgets('Send calls the callable with the entered code', (
      tester,
    ) async {
      useTallView(tester);
      final pairing = FakePairingService();
      await tester.pumpWidget(_pairingApp(signedInOverrides(pairing: pairing)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'ABC123');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pair us'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(pairing.calls, contains('requestPairing:ABC123'));
    });

    // One test per case: a loop inside a single testWidgets would leave the
    // previous sheet's modal route in the Navigator, and pumpWidget reuses the
    // element tree rather than clearing it.
    for (final entry in const {
      'caller-already-paired': 'already paired',
      'self-pairing': 'your own code',
      'request-already-pending': 'already asked',
      'code-malformed': 'six characters',
    }.entries) {
      testWidgets('${entry.key} maps to its own copy in the sheet', (
        tester,
      ) async {
        useTallView(tester);
        await tester.pumpWidget(
          _pairingApp(
            signedInOverrides(
              pairing: FakePairingService(requestError: _rejection(entry.key)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'ABC123');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pair us'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Send'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('send-error')), findsOneWidget);
        expect(
          find.textContaining(entry.value),
          findsOneWidget,
          reason: 'copy for ${entry.key}',
        );
        // The sheet stays open on failure so the code can be corrected.
        expect(find.text('Send a pairing request?'), findsOneWidget);
      });
    }
  });

  group('P2-23 — error copy is not an oracle', () {
    test('rate-limited and code-not-found are indistinguishable', () {
      final notFound = pairingErrorMessage(_rejection('code-not-found'));
      final limited = pairingErrorMessage(_rejection('rate-limited'));
      final taken = pairingErrorMessage(_rejection('owner-already-paired'));

      // If these ever diverge, the UI has rebuilt the enumeration oracle the
      // callable deliberately removed.
      expect(limited, notFound);
      expect(taken, notFound);
    });

    test('an unmapped reason still produces copy rather than blank', () {
      expect(pairingErrorMessage(_rejection('brand-new-reason')), isNotEmpty);
      expect(pairingErrorMessage(Exception('boom')), isNotEmpty);
    });
  });

  group('P2-24 — waiting state', () {
    testWidgets('pending shows the wait and says push is not coming', (
      tester,
    ) async {
      useTallView(tester);
      await tester.pumpWidget(
        _pairingApp(signedInOverrides(outgoing: fakeRequest(fromUid: 'me'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Waiting to hear back'), findsOneWidget);
      expect(find.textContaining('next time they open'), findsOneWidget);
      // The entry form is replaced, so a second request cannot be sent.
      expect(find.text('Pair us'), findsNothing);
    });

    testWidgets('Cancel calls cancelPairingRequest', (tester) async {
      useTallView(tester);
      final pairing = FakePairingService();
      await tester.pumpWidget(
        _pairingApp(
          signedInOverrides(
            pairing: pairing,
            outgoing: fakeRequest(id: 'req-9'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel request'));
      await tester.pumpAndSettle();

      expect(pairing.calls, contains('cancelPairingRequest:req-9'));
    });

    testWidgets('expired never says declined or rejected', (tester) async {
      useTallView(tester);
      await tester.pumpWidget(
        _pairingApp(
          signedInOverrides(
            outgoing: fakeRequest(status: PairingRequestStatus.expired),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('waiting-expired')), findsOneWidget);
      expect(find.text('No answer yet'), findsOneWidget);
      expect(find.text('Try another code'), findsOneWidget);

      // PI-05. These words must never reach this screen.
      for (final banned in ['declin', 'reject', 'refus', 'said no']) {
        expect(
          find.textContaining(RegExp(banned, caseSensitive: false)),
          findsNothing,
          reason: '"$banned" would tell the sender they were refused',
        );
      }
    });

    testWidgets('cancelled returns to the entry form on demand', (
      tester,
    ) async {
      useTallView(tester);
      await tester.pumpWidget(
        _pairingApp(
          signedInOverrides(
            outgoing: fakeRequest(status: PairingRequestStatus.cancelled),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('waiting-cancelled')), findsOneWidget);
      await tester.tap(find.text('Enter a code'));
      await tester.pumpAndSettle();

      expect(find.text('Pair us'), findsOneWidget);
    });
  });

  group('P2-25 — incoming requests', () {
    testWidgets('renders the sender name and both actions', (tester) async {
      useTallView(tester);
      await tester.pumpWidget(
        _pairingApp(
          signedInOverrides(incoming: [fakeRequest(fromDisplayName: 'Devon')]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Devon'), findsOneWidget);
      expect(find.text('would like to pair with you'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      // "Not now", never "Reject".
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Reject'), findsNothing);
    });

    testWidgets('several pending requests all render', (tester) async {
      useTallView(tester);
      await tester.pumpWidget(
        _pairingApp(
          signedInOverrides(
            incoming: [
              fakeRequest(id: 'r1', fromDisplayName: 'Devon'),
              fakeRequest(id: 'r2', fromDisplayName: 'Sam'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Devon'), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('Accept'), findsNWidgets(2));
    });

    testWidgets('Accept calls respondToPairing with accept true', (
      tester,
    ) async {
      useTallView(tester);
      final pairing = FakePairingService();
      await tester.pumpWidget(
        _pairingApp(
          signedInOverrides(
            pairing: pairing,
            incoming: [fakeRequest(id: 'req-7')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(pairing.calls, contains('respondToPairing:req-7:true'));
    });

    testWidgets('Not now declines rather than accepting', (tester) async {
      useTallView(tester);
      final pairing = FakePairingService();
      await tester.pumpWidget(
        _pairingApp(
          signedInOverrides(
            pairing: pairing,
            incoming: [fakeRequest(id: 'req-7')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(pairing.calls, contains('respondToPairing:req-7:false'));
    });

    testWidgets('a nameless sender renders a fallback, never a blank', (
      tester,
    ) async {
      useTallView(tester);
      await tester.pumpWidget(
        _pairingApp(
          signedInOverrides(
            incoming: [
              PairingRequest.fromFirestore('r1', {
                'fromUid': 'x',
                'toUid': 'uid-test',
                'status': 'pending',
              }),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Someone'), findsOneWidget);
    });
  });

  group('P2-26 — the paired moment', () {
    /// Drives the notifier the way the app does: through the profile stream.
    ProviderContainer containerFor(Stream<dynamic> profiles) {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(FakeUser())),
          currentUserProvider.overrideWith((ref) => profiles.cast()),
          ...pairingStreamOverrides(),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('cold start on an already-paired account shows nothing', () async {
      final container = containerFor(
        Stream.value(fakeProfile(coupleId: 'couple-1')),
      );
      container.listen(pairingCelebrationProvider, (_, _) {});
      await container.read(currentUserProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(pairingCelebrationProvider), isNull);
      expect(
        resolveRedirect(
          isLoadingAuth: false,
          isSignedIn: true,
          isLoadingProfile: false,
          profileExists: true,
          coupleId: 'couple-1',
          currentLocation: AppRoutes.splash,
          justPaired: false,
        ),
        AppRoutes.feed,
      );
    });

    test('watching coupleId appear arms the moment, once', () async {
      final controller = StreamController<dynamic>();
      addTearDown(controller.close);
      final container = containerFor(controller.stream);
      container.listen(pairingCelebrationProvider, (_, _) {});

      controller.add(fakeProfile());
      await Future<void>.delayed(Duration.zero);
      expect(container.read(pairingCelebrationProvider), isNull);

      controller.add(fakeProfile(coupleId: 'couple-1'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(pairingCelebrationProvider), 'couple-1');

      // The gate holds at /paired while it is armed.
      expect(
        resolveRedirect(
          isLoadingAuth: false,
          isSignedIn: true,
          isLoadingProfile: false,
          profileExists: true,
          coupleId: 'couple-1',
          currentLocation: AppRoutes.pairing,
          justPaired: true,
        ),
        AppRoutes.paired,
      );

      container.read(pairingCelebrationProvider.notifier).acknowledge();
      expect(container.read(pairingCelebrationProvider), isNull);

      // And never re-arms from later emissions of the same couple.
      controller.add(fakeProfile(coupleId: 'couple-1'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(pairingCelebrationProvider), isNull);
    });

    test('a missing profile document does not arm the moment', () async {
      final controller = StreamController<dynamic>();
      addTearDown(controller.close);
      final container = containerFor(controller.stream);
      container.listen(pairingCelebrationProvider, (_, _) {});

      // The gap between the account existing and its document being written.
      controller.add(null);
      await Future<void>.delayed(Duration.zero);
      controller.add(fakeProfile(coupleId: 'couple-1'));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(pairingCelebrationProvider), isNull);
    });
  });
}

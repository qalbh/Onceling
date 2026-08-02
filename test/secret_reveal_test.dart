import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/common/providers.dart';
import 'package:couple_app/features/feed/models/feed_item.dart';
import 'package:couple_app/features/secret/screens/secret_reveal_screen.dart';
import 'package:couple_app/features/secret/secret_service.dart';
import 'package:couple_app/features/secret/widgets/secret_opened_dialog.dart';
import 'package:couple_app/theme/app_theme.dart';

import 'test_doubles.dart';

/// The reveal, driven against a fake [SecretService].
///
/// Since **P3-01** the screen owns the reveal: it calls `beginReveal`, reads
/// the body inside the window that opens, and calls `completeReveal` when the
/// reading ends. So these tests assert the *transitions*, not just the
/// choreography — which of them fire, in what order, and what the reader sees
/// when one fails.
Future<SecretRevealResult?> pumpReveal(
  WidgetTester tester, {
  required FakeSecretService service,
  SecretDuration duration = SecretDuration.thirtySeconds,
  SecretState secretState = SecretState.sealed,
  TestClock? clock,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  SecretRevealResult? result;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secretServiceProvider.overrideWithValue(service),
        if (clock != null) nowProvider.overrideWithValue(clock.call),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<SecretRevealResult>(
                MaterialPageRoute(
                  builder: (_) => SecretRevealScreen(
                    secret: SecretMessage(
                      id: 'item-1',
                      senderId: 'uid-partner',
                      createdAt: DateTime(2026, 7, 30, 9, 26),
                      duration: duration,
                      secretState: secretState,
                    ),
                    senderName: 'Maya',
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400)); // route transition

  return result;
}

/// A clock the test drives, so a countdown can be advanced deterministically.
///
/// The reveal measures its window against the SERVER's `openingStartedAt`, not
/// a local stopwatch — which is correct, and means `tester.pump` alone cannot
/// move it. This is what [nowProvider] is injected for.
class TestClock {
  DateTime value = DateTime(2026, 8, 3, 12);

  DateTime call() => value;

  /// Advances both the widget's fake async time and this clock together, so
  /// the periodic tick fires *and* sees time having passed.
  Future<void> advance(WidgetTester tester, Duration by) async {
    value = value.add(by);
    await tester.pump(by);
  }
}

/// Runs the held breath and the tear, after which the reveal commits.
Future<void> advanceToReading(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1400)); // held breath ends
  await tester.pump(const Duration(milliseconds: 1000)); // tear completes
  await tester.pump(); // beginReveal + readBody resolve
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('the choreography', () {
    testWidgets('runs held breath, tear, then reading', (tester) async {
      final service = FakeSecretService();
      await pumpReveal(tester, service: service);

      expect(find.text('FROM MAYA'), findsOneWidget);
      // Both torn halves paint the whole card, so the text exists twice.
      expect(find.text('Maya wrote this for you'), findsNWidgets(2));
      expect(find.text('ONCE IT OPENS, IT IS GONE'), findsOneWidget);

      // Nothing has been committed yet — this is the point of the delay.
      expect(service.calls, isEmpty);

      await advanceToReading(tester);

      expect(find.text(service.body), findsOneWidget);
      expect(find.text('Close now'), findsOneWidget);
    });

    testWidgets('nothing is committed if the reader leaves during the tear', (
      tester,
    ) async {
      // The 2.3s of animation is the confirmation step — Q1 asked whether a
      // dialog was needed, and this is why it is not: leaving here costs
      // nothing because nothing has been written.
      final service = FakeSecretService();
      await pumpReveal(tester, service: service);
      await tester.pump(const Duration(milliseconds: 1400));

      // Abandon mid-tear.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(service.calls, isEmpty, reason: 'the secret is still sealed');
    });

    testWidgets('beginReveal fires once, after the tear, then the body', (
      tester,
    ) async {
      final service = FakeSecretService();
      await pumpReveal(tester, service: service);
      await advanceToReading(tester);

      expect(service.calls, ['beginReveal:item-1', 'readBody:item-1']);
    });
  });

  group('ending the reading', () {
    testWidgets('riding the countdown out completes the reveal', (
      tester,
    ) async {
      final clock = TestClock();
      final service = FakeSecretService(
        window: const Duration(seconds: 30),
        startedAt: clock.value,
      );
      await pumpReveal(tester, service: service, clock: clock);
      await advanceToReading(tester);

      await clock.advance(tester, const Duration(seconds: 31));
      await tester.pumpAndSettle();

      expect(service.calls.last, 'completeReveal:item-1');
      expect(find.byType(SecretRevealScreen), findsNothing);
      expect(find.text(service.body), findsNothing);
    });

    testWidgets('closing early also completes it — the body still dies', (
      tester,
    ) async {
      final service = FakeSecretService();
      await pumpReveal(tester, service: service);
      await advanceToReading(tester);

      await tester.tap(find.text('Close now'));
      await tester.pumpAndSettle();

      expect(service.calls.last, 'completeReveal:item-1');
      expect(find.byType(SecretRevealScreen), findsNothing);
    });

    testWidgets('completeReveal is called once, not twice', (tester) async {
      // The countdown hitting zero and a tap on Close can both land. The
      // callable is idempotent server-side, but popping twice is not.
      final clock = TestClock();
      final service = FakeSecretService(
        window: const Duration(seconds: 2),
        startedAt: clock.value,
      );
      await pumpReveal(tester, service: service, clock: clock);
      await advanceToReading(tester);

      await tester.tap(find.text('Close now'));
      await clock.advance(tester, const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(
        service.calls.where((c) => c.startsWith('completeReveal')).length,
        1,
      );
    });

    testWidgets('an until-closed secret has no countdown to ride out', (
      tester,
    ) async {
      final clock = TestClock();
      final service = FakeSecretService(
        window: const Duration(hours: 1),
        startedAt: clock.value,
      );
      await pumpReveal(
        tester,
        service: service,
        duration: SecretDuration.untilClosed,
        clock: clock,
      );
      await advanceToReading(tester);

      expect(
        find.text('It disappears for both of us when you close it.'),
        findsOneWidget,
      );
      // The ring shows no deadline: the server's hour ceiling is an
      // anti-retention backstop, not a reading deadline.
      expect(find.text('∞'), findsOneWidget);

      await clock.advance(tester, const Duration(seconds: 120));
      expect(find.byType(SecretRevealScreen), findsOneWidget);
    });
  });

  group('the three states', () {
    testWidgets('the body failing to load is retryable, and says the clock '
        'has started', (tester) async {
      // The sharp case: beginReveal SUCCEEDED, so the window is open and
      // running, but the read failed. The reader has lost time and deserves to
      // know it.
      var attempts = 0;
      final service = _FlakyBodyService(() => attempts++ == 0);
      await pumpReveal(tester, service: service);
      await advanceToReading(tester);

      expect(find.text('It would not open'), findsOneWidget);
      expect(find.textContaining('countdown has started'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(service.body), findsOneWidget);
      // The retry re-called beginReveal, which is safe precisely because it is
      // idempotent and does not restart the clock.
      expect(service.calls.where((c) => c.startsWith('beginReveal')).length, 2);
    });

    testWidgets('an expired window says so without blaming the reader', (
      tester,
    ) async {
      final clock = TestClock();
      final service = FakeSecretService(
        // Opened a minute ago with a 30s window: already over.
        startedAt: clock.value.subtract(const Duration(minutes: 1)),
        window: const Duration(seconds: 30),
      );
      await pumpReveal(tester, service: service, clock: clock);
      await advanceToReading(tester);

      expect(find.text('This one is gone'), findsOneWidget);
      expect(find.textContaining('that is the promise, not a fault'), findsOne);
      // Never read, so never displayed.
      expect(find.text(service.body), findsNothing);
    });

    testWidgets('a body already swept reads as gone, not as an error', (
      tester,
    ) async {
      final service = FakeSecretService(
        bodyError: const SecretBodyGoneException(),
      );
      await pumpReveal(tester, service: service);
      await advanceToReading(tester);

      expect(find.text('This one is gone'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('an already-opened secret never animates at all', (
      tester,
    ) async {
      final service = FakeSecretService();
      await pumpReveal(
        tester,
        service: service,
        secretState: SecretState.opened,
      );

      expect(find.text('Already read'), findsOneWidget);
      expect(service.calls, isEmpty, reason: 'nothing to begin');

      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Close now'), findsNothing);
    });

    testWidgets('the server refusing to begin lands on the right state', (
      tester,
    ) async {
      final service = FakeSecretService(
        beginError: Exception('failed-precondition: already-opened'),
      );
      await pumpReveal(tester, service: service);
      await advanceToReading(tester);

      expect(find.text('Already read'), findsOneWidget);
    });
  });

  testWidgets('the sender is told how it was read', (tester) async {
    // Fired by P3-01's completion on the sender's device. Pumped directly
    // because nothing on the reader's device shows it.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => SecretOpenedDialog.show(
              context,
              readerName: 'Devon',
              openedAt: '9:31 AM',
              heldFullCountdown: true,
            ),
            child: const Text('show'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();

    expect(find.text('Devon read it.'), findsOneWidget);
    expect(
      find.text('Opened at 9:31 AM. They held it for the whole countdown.'),
      findsOneWidget,
    );
  });
}

/// Fails the first body read, succeeds afterwards.
class _FlakyBodyService extends FakeSecretService {
  _FlakyBodyService(this.shouldFail);

  final bool Function() shouldFail;

  @override
  Future<String> readBody(String itemId) async {
    calls.add('readBody:$itemId');
    if (shouldFail()) throw Exception('unavailable');
    return body;
  }
}

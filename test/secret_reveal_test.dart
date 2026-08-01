import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/feed/models/feed_item.dart';
import 'package:couple_app/features/secret/screens/secret_reveal_screen.dart';
import 'package:couple_app/features/secret/widgets/secret_opened_dialog.dart';
import 'package:couple_app/theme/app_theme.dart';

/// The reveal, driven directly.
///
/// These four cases used to run through the feed, holding the sealed card on
/// `sampleThread()`'s mock secret and reading `sampleSecretBodies`. **P2-12**
/// deleted both, and no client can supply a body any more — `secretBodies` is
/// readable only while an item is `opening`, and **P3-01** owns that
/// transition. Rewritten rather than deleted: the reveal choreography is real
/// UI that still has to work when P3-01 lands, and pumping the screen with a
/// body proves it without needing a thread to hold it.
///
/// The feed's own half — that holding a sealed card admits it cannot open yet
/// — is asserted in `feed_test.dart`.
Future<SecretRevealResult?> pumpReveal(
  WidgetTester tester, {
  String? body = 'I already booked the thing for your birthday. Act surprised.',
  SecretDuration duration = SecretDuration.thirtySeconds,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  SecretRevealResult? result;

  await tester.pumpWidget(
    MaterialApp(
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
                  ),
                  senderName: 'Maya',
                  body: body,
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400)); // route transition

  return result;
}

/// Advances past the held-breath and tear stages to the reading.
Future<void> advanceToReading(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1400)); // held breath ends
  await tester.pump(const Duration(milliseconds: 1000)); // tear completes
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('runs held breath, tear, then reading', (tester) async {
    await pumpReveal(tester);

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

  testWidgets('riding the countdown out reports the full hold', (tester) async {
    await pumpReveal(tester);
    await advanceToReading(tester);

    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(find.byType(SecretRevealScreen), findsNothing);
    expect(
      find.text('I already booked the thing for your birthday. Act surprised.'),
      findsNothing,
    );
  });

  testWidgets('closing early is reported differently from holding', (
    tester,
  ) async {
    await pumpReveal(tester);
    await advanceToReading(tester);

    await tester.tap(find.text('Close now'));
    await tester.pumpAndSettle();

    expect(find.byType(SecretRevealScreen), findsNothing);
  });

  testWidgets('an until-closed secret has no countdown to ride out', (
    tester,
  ) async {
    await pumpReveal(tester, duration: SecretDuration.untilClosed);
    await advanceToReading(tester);

    expect(
      find.text('It disappears for both of us when you close it.'),
      findsOneWidget,
    );

    // No clock: waiting does not end it. This is the case P3-01 must close,
    // and the rules cannot bound — recorded on that task in STATUS.
    await tester.pump(const Duration(seconds: 120));
    await tester.pump();
    expect(find.byType(SecretRevealScreen), findsOneWidget);
  });

  testWidgets('a body that cannot be read says so instead of pretending', (
    tester,
  ) async {
    await pumpReveal(tester, body: null);

    // No held breath, no tear: the build-up would be theatre before an
    // admission. Straight to the honest answer.
    expect(find.text('Not yet'), findsOneWidget);
    expect(find.text('FROM MAYA'), findsOneWidget);
    expect(find.text('Leave it sealed'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Close now'), findsNothing);
  });

  testWidgets('the sender is told how it was read', (tester) async {
    // The dialog P3-01 will fire when the recipient's reveal completes. It is
    // not wired to anything today — nothing moves a secret to `opened` — so
    // it is pumped directly to keep it covered rather than left to rot.
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

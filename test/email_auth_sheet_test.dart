import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/common/providers.dart';
import 'package:couple_app/features/auth/auth_service.dart';
import 'package:couple_app/features/auth/screens/sign_in_screen.dart';
import 'package:couple_app/features/auth/widgets/email_auth_sheet.dart';
import 'package:couple_app/theme/app_theme.dart';

/// Stands in for Firebase. Records calls, and can stall or fail on demand.
class FakeAuthService implements AuthService {
  FakeAuthService({this.failure, this.completer});

  /// Thrown by signIn/signUp when set.
  final AuthFailure? failure;

  /// When set, calls hang until it completes — lets a test observe loading.
  final Completer<void>? completer;

  final List<String> calls = [];

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> recoverProfile() async {
    calls.add('recoverProfile');
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    calls.add('signIn:$email');
    if (completer != null) await completer!.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    calls.add('signUp:$email:$displayName');
    if (completer != null) await completer!.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<void> signOut() async => calls.add('signOut');
}

Future<void> pumpSheet(WidgetTester tester, FakeAuthService service) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authServiceProvider.overrideWithValue(service)],
      child: MaterialApp(theme: AppTheme.light(), home: const SignInScreen()),
    ),
  );
  await tester.tap(find.text('Use email or phone'));
  await tester.pumpAndSettle();
}

FilledButton submitButton(WidgetTester tester) {
  return tester.widget<FilledButton>(find.byType(FilledButton).last);
}

void main() {
  testWidgets('the email path opens from the sign-in screen', (tester) async {
    await pumpSheet(tester, FakeAuthService());
    expect(find.byType(EmailAuthSheet), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('empty: submit is disabled until both fields have content', (
    tester,
  ) async {
    await pumpSheet(tester, FakeAuthService());
    expect(submitButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'a@b.test');
    await tester.pump();
    expect(submitButton(tester).onPressed, isNull, reason: 'password is blank');

    await tester.enterText(find.byType(TextField).last, 'hunter22');
    await tester.pump();
    expect(submitButton(tester).onPressed, isNotNull);
  });

  testWidgets('whitespace alone does not enable submit', (tester) async {
    await pumpSheet(tester, FakeAuthService());
    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.enterText(find.byType(TextField).last, 'hunter22');
    await tester.pump();
    expect(submitButton(tester).onPressed, isNull);
  });

  testWidgets('loading: progress shows, inputs disable, no double submit', (
    tester,
  ) async {
    final gate = Completer<void>();
    final service = FakeAuthService(completer: gate);
    await pumpSheet(tester, service);

    await tester.enterText(find.byType(TextField).first, 'a@b.test');
    await tester.enterText(find.byType(TextField).last, 'hunter22');
    await tester.pump();
    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull, reason: 'no double submit');
    final email = tester.widget<TextField>(find.byType(TextField).first);
    expect(email.enabled, isFalse, reason: 'inputs disabled while in flight');

    gate.complete();
    await tester.pumpAndSettle();
    expect(service.calls, ['signIn:a@b.test']);
  });

  testWidgets('error: a failure shows a human message, not a code', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      FakeAuthService(
        failure: const AuthFailure(
          'That email and password do not match an account.',
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'a@b.test');
    await tester.enterText(find.byType(TextField).last, 'wrong');
    await tester.pump();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(
      find.text('That email and password do not match an account.'),
      findsOneWidget,
    );
    // The sheet stays open so the password can be corrected.
    expect(find.byType(EmailAuthSheet), findsOneWidget);
    // And it is usable again.
    expect(submitButton(tester).onPressed, isNotNull);
  });

  testWidgets('switching to sign-up asks for a name and calls signUp', (
    tester,
  ) async {
    final service = FakeAuthService();
    await pumpSheet(tester, service);

    await tester.tap(find.text('Create an account instead'));
    await tester.pumpAndSettle();
    expect(find.text('Make an account'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));

    await tester.enterText(find.byType(TextField).at(0), 'Alice');
    await tester.enterText(find.byType(TextField).at(1), 'a@b.test');
    await tester.enterText(find.byType(TextField).at(2), 'hunter22');
    await tester.pump();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(service.calls, ['signUp:a@b.test:Alice']);
  });

  testWidgets('a successful sign-in does not dismiss the sheet itself', (
    tester,
  ) async {
    final service = FakeAuthService();
    await pumpSheet(tester, service);

    await tester.enterText(find.byType(TextField).first, 'a@b.test');
    await tester.enterText(find.byType(TextField).last, 'hunter22');
    await tester.pump();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(service.calls, contains('signIn:a@b.test'));
    // The sheet no longer pops itself. In the app the gate replaces the page
    // stack and that disposes it; this harness has no gate, so it stays — and
    // that is the correct outcome here. Popping on success was a race against
    // the replacement, which is what crashed on first sign-in.
    // The real dismissal is asserted in router_signin_test.dart, through the
    // provider graph with a live gate.
    expect(find.byType(EmailAuthSheet), findsOneWidget);
    expect(find.text('Something went wrong. Try again.'), findsNothing);
  });

  testWidgets('Apple stays disabled, Google is wired (P2-19)', (tester) async {
    // Rewritten at P2-19. This used to assert BOTH were disabled. Google now
    // works; Apple still needs a paid Apple Developer account (**P2-20**), and
    // a button that opens nothing is worse than one visibly unavailable.
    final auth = _RecordingAuth();
    // A real viewport: at 800x600 these buttons fall below the fold and taps
    // silently miss, which the sheet helper already learned the hard way.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: MaterialApp(theme: AppTheme.light(), home: const SignInScreen()),
      ),
    );

    final apple = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Continue with Apple'),
        matching: find.byType(FilledButton),
      ),
    );
    final google = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Continue with Google'),
        matching: find.byType(OutlinedButton),
      ),
    );

    expect(apple.onPressed, isNull, reason: 'P2-20 has not wired Apple');
    expect(google.onPressed, isNotNull, reason: 'P2-19 wired Google');

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(auth.calls, contains('signInWithGoogle'));
  });

  testWidgets('a cancelled Google sign-in shows no error', (tester) async {
    // Backing out of the account picker is a decision, not a fault. The
    // service returns normally on cancel; the screen must stay quiet.
    final auth = _RecordingAuth();
    // A real viewport: at 800x600 these buttons fall below the fold and taps
    // silently miss, which the sheet helper already learned the hard way.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: MaterialApp(theme: AppTheme.light(), home: const SignInScreen()),
      ),
    );

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.textContaining('went wrong'), findsNothing);
  });

  testWidgets('a failed Google sign-in says so', (tester) async {
    final auth = _RecordingAuth(
      error: const AuthFailure('Google sign-in is unavailable on this device.'),
    );
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: MaterialApp(theme: AppTheme.light(), home: const SignInScreen()),
      ),
    );

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(
      find.text('Google sign-in is unavailable on this device.'),
      findsOneWidget,
    );
  });
}

/// Records which auth path the sign-in screen took.
class _RecordingAuth implements AuthService {
  _RecordingAuth({this.error});

  final Object? error;
  final List<String> calls = [];

  @override
  Future<void> signInWithGoogle() async {
    calls.add('signInWithGoogle');
    if (error case final failure?) throw failure;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    calls.add('signIn');
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async => calls.add('signUp');

  @override
  Future<void> signOut() async => calls.add('signOut');

  @override
  Future<void> recoverProfile() async => calls.add('recoverProfile');
}

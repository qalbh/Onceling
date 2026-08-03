import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/common/app_router.dart';
import 'package:couple_app/common/providers.dart';
import 'package:couple_app/features/auth/auth_service.dart';
import 'package:couple_app/features/auth/models/user_profile.dart';
import 'package:couple_app/features/auth/widgets/email_auth_sheet.dart';
import 'package:couple_app/theme/app_theme.dart';

import 'test_doubles.dart';

/// Signing in through the real sheet, through `routerProvider`, in the
/// signed-out → signed-in direction.
///
/// This direction was untested and is the one that crashed on device: the sheet
/// is a pageless route on the `/` page, and a successful sign-in makes the gate
/// replace that page twice (`/` → `/splash` → `/pairing`) while the sheet is
/// still awaiting. The sheet used to pop itself afterwards, into a Navigator
/// mid-rebuild.
///
/// **These tests do not try to reproduce the race.** A fake service returns in
/// milliseconds and collapses both replacements into one settle, so the timing
/// never lines up — four attempts confirmed that. They assert the invariant
/// instead: a successful sign-in reaches the right destination with the sheet
/// gone and no exception. That holds regardless of timing.
///
/// Note what these do *not* catch: putting the pop back leaves all four green,
/// because the gate has already disposed the sheet by then and `mounted` is
/// false either way. The source assertion below is what pins that.
void main() {
  /// Emits on the auth stream the way Firebase does — during `signIn()`, before
  /// it returns — so the gate moves while the sheet is still mounted.
  Widget app({
    required StreamController<User?> auth,
    required StreamController<UserProfile?> profiles,
    required AuthService service,
  }) {
    return ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) async* {
          yield null;
          yield* auth.stream;
        }),
        currentUserProvider.overrideWith((ref) async* {
          yield null;
          yield* profiles.stream;
        }),
        authServiceProvider.overrideWithValue(service),
        pairingServiceProvider.overrideWithValue(FakePairingService()),
        // P3-04: the gate starts push registration, which otherwise reaches
        // FirebaseMessaging.instance with no Firebase app.
        pushServiceProvider.overrideWithValue(FakePushService()),
        ...pairingStreamOverrides(),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: ref.watch(routerProvider),
        ),
      ),
    );
  }

  /// A real device viewport. At the default 800x600 the "Use email or phone"
  /// button falls below the fold and taps silently miss it — that cost a
  /// misdiagnosis once.
  void useDeviceView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> signInThroughSheet(
    WidgetTester tester, {
    required StreamController<User?> auth,
    required StreamController<UserProfile?> profiles,
    required AuthService service,
  }) async {
    await tester.pumpWidget(
      app(auth: auth, profiles: profiles, service: service),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.byType(EmailAuthSheet), findsNothing);
    await tester.tap(find.text('Use email or phone'));
    await tester.pumpAndSettle();
    expect(find.byType(EmailAuthSheet), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'a@b.test');
    await tester.enterText(find.byType(TextField).last, 'hunter22');
    await tester.pump();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
  }

  testWidgets('sign-in reaches pairing, sheet gone, no exception', (
    tester,
  ) async {
    useDeviceView(tester);
    final auth = StreamController<User?>.broadcast();
    final profiles = StreamController<UserProfile?>.broadcast();
    addTearDown(auth.close);
    addTearDown(profiles.close);

    await signInThroughSheet(
      tester,
      auth: auth,
      profiles: profiles,
      service: _StreamAuth(auth, profiles, profile: () => fakeProfile()),
    );

    // The gate moved the user; the sheet went with the page it was attached to.
    expect(find.text('Find your person'), findsOneWidget);
    expect(find.byType(EmailAuthSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an already-paired account lands on the feed, not pairing', (
    tester,
  ) async {
    useDeviceView(tester);
    final auth = StreamController<User?>.broadcast();
    final profiles = StreamController<UserProfile?>.broadcast();
    addTearDown(auth.close);
    addTearDown(profiles.close);

    await signInThroughSheet(
      tester,
      auth: auth,
      profiles: profiles,
      service: _StreamAuth(
        auth,
        profiles,
        profile: () => fakeProfile(coupleId: 'couple-1'),
      ),
    );

    // Signing in on an already-paired account is not a fresh pairing, so the
    // moment must stay down (P2-26) and the feed opens directly.
    expect(find.text('Find your person'), findsNothing);
    expect(find.byType(EmailAuthSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign-up reaches pairing through the same path', (tester) async {
    useDeviceView(tester);
    final auth = StreamController<User?>.broadcast();
    final profiles = StreamController<UserProfile?>.broadcast();
    addTearDown(auth.close);
    addTearDown(profiles.close);

    await tester.pumpWidget(
      app(
        auth: auth,
        profiles: profiles,
        service: _StreamAuth(auth, profiles, profile: () => fakeProfile()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use email or phone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create an account instead'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Alice');
    await tester.enterText(find.byType(TextField).at(1), 'a@b.test');
    await tester.enterText(find.byType(TextField).at(2), 'hunter22');
    await tester.pump();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Find your person'), findsOneWidget);
    expect(find.byType(EmailAuthSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // A source assertion, deliberately, because a behavioural one is impossible.
  //
  // Reintroducing the pop does NOT fail the tests above: by the time the await
  // returns, the gate has already disposed the sheet, so `mounted` is false and
  // the pop is skipped — the observable outcome is identical. Verified by
  // sabotage: putting the pop back leaves all four green. The crash needs the
  // race to land inside a window a fake service cannot produce.
  //
  // So the only way to pin this is to assert the call is absent.
  test('the sheet never calls Navigator directly', () {
    final source = File(
      'lib/features/auth/widgets/email_auth_sheet.dart',
    ).readAsStringSync();
    final code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .where((line) => !line.trimLeft().startsWith('///'))
        .join('\n');

    expect(
      code.contains('Navigator.of('),
      isFalse,
      reason:
          'Popping this sheet races the gate replacing the page stack. '
          'Dismissal is the gate\'s job — see the class comment.',
    );
  });

  testWidgets('a failed sign-in keeps the sheet open with its error', (
    tester,
  ) async {
    useDeviceView(tester);
    final auth = StreamController<User?>.broadcast();
    final profiles = StreamController<UserProfile?>.broadcast();
    addTearDown(auth.close);
    addTearDown(profiles.close);

    await signInThroughSheet(
      tester,
      auth: auth,
      profiles: profiles,
      service: _FailingAuth(),
    );

    // Nothing navigated, so the sheet is still the user's context for fixing
    // what went wrong. Removing the success-path pop must not touch this.
    expect(find.byType(EmailAuthSheet), findsOneWidget);
    expect(
      find.text('That email and password do not match an account.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

/// Pushes onto the auth and profile streams mid-call, as Firebase does.
class _StreamAuth implements AuthService {
  _StreamAuth(this.auth, this.profiles, {required this.profile});

  final StreamController<User?> auth;
  final StreamController<UserProfile?> profiles;
  final UserProfile Function() profile;

  Future<void> _flip() async {
    auth.add(FakeUser());
    // A beat, so the gate's first replacement lands before this returns —
    // the shape device traces showed, compressed.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    profiles.add(profile());
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  @override
  Future<void> signIn({required String email, required String password}) =>
      _flip();

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) => _flip();

  @override
  Future<void> signOut() async => auth.add(null);

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> recoverProfile() async {}
}

class _FailingAuth implements AuthService {
  @override
  Future<void> signIn({required String email, required String password}) async {
    throw const AuthFailure('That email and password do not match an account.');
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async => signIn(email: email, password: password);

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> recoverProfile() async {}
}

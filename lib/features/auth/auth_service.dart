import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../pairing/pairing_service.dart';
import 'profile_service.dart';

/// An auth problem already translated into something a person can read.
///
/// The UI never sees a `FirebaseAuthException` code — "wrong-password" is a
/// wire value, not a sentence.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => 'AuthFailure: $message';
}

/// What the UI needs from auth.
///
/// An interface so widget tests can substitute a fake without a live Firebase —
/// [FirebaseAuthService] is the only real implementation.
abstract interface class AuthService {
  Future<void> signIn({required String email, required String password});

  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  });

  /// Google sign-in (**P2-19**).
  ///
  /// Returns normally when the person backs out of the account picker — a
  /// cancelled sign-in is not a failure and must not raise an error banner.
  Future<void> signInWithGoogle();

  Future<void> signOut();

  /// Re-runs the **P2-30** profile write for the already-signed-in user
  /// (**P2-34**).
  ///
  /// Recovery for an account whose `users/{uid}` document is missing — the
  /// sign-up that died between creating the account and writing the document.
  /// Retrying a read cannot fix that: the document does not exist to appear.
  ///
  /// Safe to expose because it is the *same* write `signIn` already performs
  /// on every sign-in, and [FirebaseAuthService.ensureProfile] returns an
  /// existing document untouched rather than clobbering it. Anyone worried
  /// about this button should be equally worried about signing in.
  Future<void> recoverProfile();
}

/// Email/password sign-in, sign-up and sign-out, plus the `users/{uid}`
/// document that has to exist before anything else in Phase 2 works.
class FirebaseAuthService implements AuthService {
  const FirebaseAuthService(this._auth, this._profiles, this._pairing);

  final FirebaseAuth _auth;
  final ProfileService _profiles;
  final PairingService _pairing;

  @override
  Future<void> signIn({required String email, required String password}) async {
    final credential = await _guard(
      () => _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );

    // Defensive: an account can exist in Auth with no document — created before
    // this code shipped, or a sign-up that died between the two steps.
    final user = credential.user;
    if (user != null) await _settleProfile(user);
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final credential = await _guard(
      () => _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );

    final user = credential.user;
    if (user != null) await _settleProfile(user, displayName: displayName);
  }

  /// **P2-19** — Google, landing in exactly the same place as email.
  ///
  /// The important line is the last one: [_settleProfile]. A Google sign-in
  /// creates the SAME `users/{uid}` document by the SAME route — the
  /// `ensureUserProfile` callable — so there is no second shape of user in the
  /// database. That matters more than it looks: `ensureUserProfile` writes a
  /// fixed literal server-side (**P2-35**), so a provider that bypassed it
  /// would be the only way a differently-shaped profile could ever exist.
  ///
  /// The display name comes from the Google account when Firebase has one, and
  /// the server falls back to the token's name or the email's local part —
  /// never to a client-supplied identity.
  @override
  Future<void> signInWithGoogle() async {
    final GoogleSignInAccount account;
    try {
      // v7 requires initialize() before any authentication call. No client id
      // is passed: the google-services Gradle plugin emits the WEB client as
      // `R.string.default_web_client_id`, and iOS reads CLIENT_ID from
      // GoogleService-Info.plist. Both files are gitignored, so passing one
      // here would mean pasting a value out of them.
      await GoogleSignIn.instance.initialize();
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (error) {
      // Backing out of the picker is a decision, not a fault.
      if (error.code == GoogleSignInExceptionCode.canceled) return;
      throw AuthFailure(_googleMessageFor(error.code));
    }

    final credential = await _guard(
      () => _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: account.authentication.idToken),
      ),
    );

    final user = credential.user;
    if (user != null) {
      await _settleProfile(user, displayName: user.displayName);
    }
  }

  @override
  Future<void> signOut() async {
    // Sign out of Google too. Without this the account picker is skipped on
    // the next attempt and the previous person is silently re-selected — on a
    // shared device that is somebody else's account.
    try {
      await GoogleSignIn.instance.signOut();
    } catch (error) {
      developer.log('google signOut failed: $error', name: 'AuthService');
    }
    await _auth.signOut();
  }

  static String _googleMessageFor(GoogleSignInExceptionCode code) =>
      switch (code) {
        GoogleSignInExceptionCode.canceled => 'Sign-in cancelled.',
        GoogleSignInExceptionCode.interrupted =>
          'Sign-in was interrupted. Try again.',
        GoogleSignInExceptionCode.clientConfigurationError =>
          'Google sign-in is not configured for this build.',
        GoogleSignInExceptionCode.providerConfigurationError =>
          'Google sign-in is unavailable on this device.',
        GoogleSignInExceptionCode.uiUnavailable =>
          'Could not open the Google sign-in screen.',
        GoogleSignInExceptionCode.userMismatch =>
          'That is a different account than the one expected.',
        _ => 'Something went wrong with Google sign-in. Try again.',
      };

  @override
  Future<void> recoverProfile() async {
    final user = _auth.currentUser;
    // Nothing to recover for a signed-out caller; the gate already sends them
    // to sign-in.
    if (user == null) return;
    await _settleProfile(user);
  }

  /// Profile document, then pairing code — the P2-30 write followed by the
  /// P2-08 claim, both idempotent, both server-side.
  ///
  /// The profile write is a callable rather than a client write (**P2-35**):
  /// recreating a missing profile has to restore the caller's real `coupleId`,
  /// and the client can neither read it nor write it. Name resolution moved
  /// with it — the server reads the auth token, so the only thing the client
  /// chooses is the name the person typed.
  Future<void> _settleProfile(User user, {String? displayName}) async {
    final profile = await _profiles.ensureProfile(displayName: displayName);

    // Only the unpaired-and-codeless need a code. Failure here is not fatal:
    // the pairing screen retries the same idempotent callable.
    if (profile.coupleId == null && profile.pairingCode == null) {
      try {
        await _pairing.ensurePairingCode();
      } catch (error) {
        developer.log(
          'ensurePairingCode after sign-in failed: $error',
          name: 'AuthService',
        );
      }
    }
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_messageFor(error.code));
    }
  }

  static String _messageFor(String code) => switch (code) {
    // Recent Firebase collapses wrong-password and user-not-found into
    // invalid-credential so a stranger cannot probe which emails exist. Keep
    // the older codes mapped too — older projects still emit them.
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'That email and password do not match an account.',
    'email-already-in-use' =>
      'That email already has an account. Sign in instead.',
    'weak-password' => 'Passwords need to be at least six characters.',
    'invalid-email' => 'That does not look like an email address.',
    'user-disabled' => 'That account has been disabled.',
    'too-many-requests' => 'Too many attempts. Wait a moment and try again.',
    'network-request-failed' =>
      'No connection. Check your network and try again.',
    'operation-not-allowed' => 'Email sign-in is not enabled for this project.',
    _ => 'Something went wrong signing you in. Try again.',
  };
}

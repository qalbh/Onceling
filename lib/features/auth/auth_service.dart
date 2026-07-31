import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';

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

  @override
  Future<void> signOut() => _auth.signOut();

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

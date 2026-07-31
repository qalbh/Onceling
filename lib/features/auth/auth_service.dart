import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../pairing/pairing_service.dart';
import 'models/user_profile.dart';

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
}

/// Email/password sign-in, sign-up and sign-out, plus the `users/{uid}`
/// document that has to exist before anything else in Phase 2 works.
class FirebaseAuthService implements AuthService {
  const FirebaseAuthService(this._auth, this._firestore, this._pairing);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
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

  /// Profile document, then pairing code — the P2-30 write followed by the
  /// P2-08 claim, both idempotent.
  Future<void> _settleProfile(User user, {String? displayName}) async {
    final profile = await ensureProfile(user, displayName: displayName);

    // Only the unpaired-and-codeless need a code. Failure here is not fatal:
    // the pairing screen retries the same idempotent callable.
    if (profile['coupleId'] == null && profile['pairingCode'] == null) {
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

  /// Creates `users/{uid}` if it is missing. Idempotent — signing in again
  /// leaves an existing document untouched rather than clobbering it. Returns
  /// the document's data either way.
  Future<Map<String, dynamic>> ensureProfile(
    User user, {
    String? displayName,
  }) async {
    final document = _firestore.collection('users').doc(user.uid);

    final existing = await document.get();
    if (existing.exists) return existing.data() ?? {};

    final data = UserProfile.initialDocument(
      displayName: _resolveDisplayName(user, displayName),
      createdAt: FieldValue.serverTimestamp(),
    );
    await document.set(data);
    return data;
  }

  /// Sign-up input, else whatever the provider gave us, else the email's
  /// local-part. Never empty — Security Rules reject a blank display name.
  String _resolveDisplayName(User user, String? provided) {
    final candidates = [
      provided,
      user.displayName,
      user.email?.split('@').first,
    ];
    for (final candidate in candidates) {
      final trimmed = candidate?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
    }
    return 'Someone';
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

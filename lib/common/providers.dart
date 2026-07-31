import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_service.dart';
import '../features/auth/models/user_profile.dart';
import '../features/pairing/pairing_service.dart';

/// Riverpod roots for the Firebase SDKs.
///
/// Deliberately plain declarations — no `@riverpod`, no `build_runner`. Reading
/// the SDKs through providers rather than calling `.instance` inside widgets is
/// what makes them overridable in tests and in the emulator.

/// The signed-in session's auth handle.
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

/// The Firestore handle. Everything that reads or writes a document goes
/// through this rather than touching `FirebaseFirestore.instance` directly.
final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

/// Emits on sign-in, sign-out, and token refresh. Null means signed out.
///
/// This is the stream the auth gate will redirect on at **P2-14**.
final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(firebaseAuthProvider).authStateChanges(),
);

/// The Cloud Functions handle, already emulator-wired by `main()` in debug.
final functionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instance,
);

/// Client edge of the pairing callables.
final pairingServiceProvider = Provider<PairingService>(
  (ref) => FirebaseFunctionsPairingService(ref.watch(functionsProvider)),
);

/// Email/password operations and first-sign-in profile creation.
final authServiceProvider = Provider<AuthService>(
  (ref) => FirebaseAuthService(
    ref.watch(firebaseAuthProvider),
    ref.watch(firestoreProvider),
    ref.watch(pairingServiceProvider),
  ),
);

/// The signed-in user's `users/{uid}` document, following [authStateProvider].
///
/// Emits null when signed out, and null in the gap between the account existing
/// and its document being written. Anything downstream must handle both.
final currentUserProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream<UserProfile?>.value(null);

  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(user.uid)
      .snapshots()
      .map(
        (snapshot) => snapshot.exists
            ? UserProfile.fromFirestore(snapshot.id, snapshot.data()!)
            : null,
      );
});

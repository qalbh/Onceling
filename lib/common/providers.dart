import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

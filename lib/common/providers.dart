import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_service.dart';
import '../features/auth/models/user_profile.dart';
import '../features/auth/profile_service.dart';
import '../features/mood/mood_service.dart';
import '../features/notifications/push_service.dart';
import '../features/pairing/models/pairing_request.dart';
import '../features/pairing/pairing_service.dart';
import '../features/secret/secret_service.dart';

/// Riverpod roots for the Firebase SDKs.
///
/// Deliberately plain declarations — no `@riverpod`, no `build_runner`. Reading
/// the SDKs through providers rather than calling `.instance` inside widgets is
/// what makes them overridable in tests and in the emulator.

/// The clock, behind a provider so tests can pin it.
///
/// Shared rather than per-feature since **P3-01**: the anniversary line counts
/// days from it, and the secret reveal's countdown measures a window against
/// it. A countdown that read `DateTime.now()` directly could not be tested at
/// all — `tester.pump` advances the fake async clock, never the wall clock.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

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

/// The region the callables are deployed to.
///
/// **Must match `setGlobalOptions` in `functions/src/index.ts`**, and both must
/// match the Firestore location in `firebase.json`. A mismatch does not fail
/// loudly: `FirebaseFunctions.instance` defaults to `us-central1`, so the app
/// would keep working while every call crossed a continent to reach a database
/// in `asia-south1`. Found on the first real deploy (**P2-16**).
const functionsRegion = 'asia-south1';

/// The Cloud Functions handle, already emulator-wired by `main()` in debug.
final functionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instanceFor(region: functionsRegion),
);

/// Client edge of the pairing callables.
final pairingServiceProvider = Provider<PairingService>(
  (ref) => FirebaseFunctionsPairingService(ref.watch(functionsProvider)),
);

/// Client edge of FCM registration (**P3-04**).
final pushServiceProvider = Provider<PushService>(
  (ref) => FirebasePushService(
    FirebaseMessaging.instance,
    ref.watch(firestoreProvider),
  ),
);

/// Keeps `users/{uid}.pushToken` in step with the session (**P3-04**).
///
/// Watches auth rather than being called from each sign-in path, so a new one
/// cannot forget it — Google sign-in landed after this and needed no change.
/// Sign-out clears the token, which is the case that actually matters: a stale
/// token keeps delivering a couple's notifications to a handset somebody else
/// may now be holding.
final pushRegistrationProvider = Provider<void>((ref) {
  final service = ref.watch(pushServiceProvider);
  StreamSubscription<String>? refresh;
  String? registeredFor;

  ref.onDispose(() => refresh?.cancel());

  ref.listen<AsyncValue<User?>>(authStateProvider, (previous, next) {
    final user = next.valueOrNull;
    final previousUid = previous?.valueOrNull?.uid;

    if (user == null) {
      refresh?.cancel();
      refresh = null;
      final leaving = previousUid ?? registeredFor;
      registeredFor = null;
      if (leaving != null) unawaited(service.unregister(uid: leaving));
      return;
    }

    if (registeredFor == user.uid) return;
    registeredFor = user.uid;
    unawaited(service.register(uid: user.uid));

    refresh?.cancel();
    // FCM rotates without asking. A token we do not follow silently stops
    // working, and the person never learns why push went quiet.
    refresh = service.onTokenRefresh.listen((token) {
      if (service is FirebasePushService) {
        unawaited(service.store(uid: user.uid, token: token));
      }
    });
  }, fireImmediately: true);
});

/// Client edge of the two reveal transitions (**P3-01**).
final secretServiceProvider = Provider<SecretService>(
  (ref) => FirebaseSecretService(
    ref.watch(functionsProvider),
    ref.watch(firestoreProvider),
  ),
);

/// Client edge of the mood callable (**P2-12**).
final moodServiceProvider = Provider<MoodService>(
  (ref) => FirebaseFunctionsMoodService(ref.watch(functionsProvider)),
);

/// Client edge of the server-side profile write (**P2-30**, **P2-35**).
final profileServiceProvider = Provider<ProfileService>(
  (ref) => FirebaseFunctionsProfileService(ref.watch(functionsProvider)),
);

/// Email/password operations and first-sign-in profile creation.
final authServiceProvider = Provider<AuthService>(
  (ref) => FirebaseAuthService(
    ref.watch(firebaseAuthProvider),
    ref.watch(profileServiceProvider),
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

/// Pending requests addressed to the signed-in user (**P2-25**).
///
/// A list, not a single document: several people can be asking at once, and
/// the accept transaction expires the losers rather than the UI hiding them.
///
/// The `toUid == me` filter is not cosmetic. Rules grant `list` only for a
/// query that provably stays inside the caller's own requests, so dropping it
/// does not return more rows — it returns permission-denied.
final incomingRequestsProvider = StreamProvider<List<PairingRequest>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);

  return ref
      .watch(firestoreProvider)
      .collection('pairingRequests')
      .where('toUid', isEqualTo: user.uid)
      .where('status', isEqualTo: 'pending')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => PairingRequest.fromFirestore(doc.id, doc.data()))
            .toList(),
      );
});

/// The caller's most recently sent request, whatever its status (**P2-24**).
///
/// Deliberately *not* filtered to pending. The sender has to see the moment it
/// becomes `expired` — filtering to pending would make a settled request
/// silently vanish, which reads as the app losing it rather than answering.
final outgoingRequestProvider = StreamProvider<PairingRequest?>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(null);

  return ref
      .watch(firestoreProvider)
      .collection('pairingRequests')
      .where('fromUid', isEqualTo: user.uid)
      .orderBy('createdAt', descending: true)
      .limit(1)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.isEmpty
            ? null
            : PairingRequest.fromFirestore(
                snapshot.docs.first.id,
                snapshot.docs.first.data(),
              ),
      );
});

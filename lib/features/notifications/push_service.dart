import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// The device's FCM registration token, and where it lives (**P3-04**).
///
/// Brief §9 puts `pushToken` on `users/{uid}`. Three operations, and the third
/// is the one that matters:
///
/// - **store** it after sign-in,
/// - **refresh** it when FCM rotates it, which it does without asking,
/// - **clear** it on sign-out. A stale token keeps delivering that account's
///   notifications to a handset somebody else may now be holding. On a product
///   whose whole subject is a private space for two people, that is the worst
///   available bug, and it is silent.
abstract interface class PushService {
  /// Asks for permission and returns the token, or null if refused or
  /// unavailable.
  ///
  /// Null is ordinary, not exceptional: a declined prompt, a simulator with no
  /// APNs, or a device with no Play services all land here.
  Future<String?> register({required String uid});

  /// Drops the token from the profile and from the device.
  Future<void> unregister({required String uid});

  /// Fires when FCM rotates the token mid-session.
  Stream<String> get onTokenRefresh;
}

class FirebasePushService implements PushService {
  FirebasePushService(this._messaging, this._db);

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _db;

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<String?> register({required String uid}) async {
    try {
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        // Declining is a legitimate choice. Clear any token from a previous
        // decision so we do not keep sending to a device that said no.
        await unregister(uid: uid);
        return null;
      }

      final token = await _messaging.getToken();
      if (token == null) {
        // iOS without APNs lands here — see P3-04's note in STATUS. Not an
        // error, just nothing to store yet.
        developer.log('no FCM token available', name: 'PushService');
        return null;
      }
      await store(uid: uid, token: token);
      return token;
    } catch (error) {
      // Push is an enhancement; failing to arrange it must never stop someone
      // signing in.
      developer.log('push registration failed: $error', name: 'PushService');
      return null;
    }
  }

  /// Writes the token onto the profile.
  ///
  /// A merge rather than an update: the field may not exist yet, and this must
  /// not disturb anything else on the document.
  Future<void> store({required String uid, required String token}) async {
    await _db.collection('users').doc(uid).set({
      'pushToken': token,
      'pushTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> unregister({required String uid}) async {
    // Order matters. Clear the server's copy FIRST: if deleting the local
    // token succeeded and the profile write then failed, the account would
    // keep a token nobody can reach but the fan-out would keep targeting it.
    try {
      await _db.collection('users').doc(uid).set({
        'pushToken': FieldValue.delete(),
        'pushTokenUpdatedAt': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (error) {
      developer.log('clearing pushToken failed: $error', name: 'PushService');
    }

    try {
      await _messaging.deleteToken();
    } catch (error) {
      developer.log('deleteToken failed: $error', name: 'PushService');
    }
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// What `beginReveal` hands back: the server's clock, not the device's.
///
/// The countdown is driven from [openingStartedAt] rather than from a local
/// stopwatch started when the animation ended. They drift, and the one that
/// matters is the server's — the Security Rule compares `request.time` against
/// this exact value, so a client counting from its own clock would keep showing
/// time remaining after the body had already stopped being readable.
class RevealWindow {
  const RevealWindow({
    required this.openingStartedAt,
    required this.window,
    required this.alreadyOpening,
  });

  final DateTime openingStartedAt;

  /// How long the window runs. Never null — `untilClosed` reports the server's
  /// hour ceiling rather than "forever", because forever is not what happens.
  final Duration window;

  /// True when this call found the secret already opening and returned the
  /// existing start time instead of stamping a new one.
  final bool alreadyOpening;

  Duration remainingAt(DateTime now) {
    final left = openingStartedAt.add(window).difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  bool hasExpiredAt(DateTime now) => remainingAt(now) == Duration.zero;
}

/// Client edge of the two reveal transitions (**P3-01**).
///
/// Both are callables because neither is expressible as a client write: item
/// `update` is restricted to the caller's own reaction key, so nothing on a
/// device can set `secretState` in either direction. The body read is a plain
/// Firestore get, permitted only while the item is `opening` and only for the
/// recipient — the same window these callables open and close.
abstract interface class SecretService {
  /// `sealed -> opening`. Starts the read window and returns it.
  ///
  /// Idempotent: calling it again on a secret already opening returns the
  /// existing window rather than restarting the clock. That is what makes a
  /// retry after a failed body read safe.
  Future<RevealWindow> beginReveal(String itemId);

  /// Reads `secretBodies/{itemId}`. Only succeeds inside the window.
  Future<String> readBody(String itemId);

  /// `opening -> opened`. Destroys the body, keeps the tombstone.
  ///
  /// Idempotent: an already-opened secret succeeds silently, which is what
  /// makes a double call on a flaky connection harmless.
  Future<void> completeReveal(String itemId);
}

class FirebaseSecretService implements SecretService {
  const FirebaseSecretService(this._functions, this._db);

  final FirebaseFunctions _functions;
  final FirebaseFirestore _db;

  @override
  Future<RevealWindow> beginReveal(String itemId) async {
    final result = await _functions.httpsCallable('beginReveal').call({
      'itemId': itemId,
    });
    final data = result.data as Map;

    final startedAtMs = (data['openingStartedAt'] as num?)?.toInt();
    if (startedAtMs == null) {
      // The server stamped a timestamp it could not read back. Better to fail
      // loudly than to run a countdown from a guessed start.
      throw StateError('beginReveal returned no openingStartedAt');
    }

    return RevealWindow(
      openingStartedAt: DateTime.fromMillisecondsSinceEpoch(startedAtMs),
      window: Duration(seconds: (data['windowSeconds'] as num).toInt()),
      alreadyOpening: data['alreadyOpening'] as bool? ?? false,
    );
  }

  @override
  Future<String> readBody(String itemId) async {
    final snap = await _db.collection('secretBodies').doc(itemId).get();
    if (!snap.exists) {
      // Already swept, or already completed elsewhere. Not an error the reader
      // can act on, so it is reported as its own state rather than a failure.
      throw const SecretBodyGoneException();
    }
    return snap.data()?['body'] as String? ?? '';
  }

  @override
  Future<void> completeReveal(String itemId) async {
    await _functions.httpsCallable('completeReveal').call({'itemId': itemId});
  }
}

/// The body is not there any more — swept, or completed on another device.
class SecretBodyGoneException implements Exception {
  const SecretBodyGoneException();

  @override
  String toString() => 'SecretBodyGoneException: the body is already gone';
}

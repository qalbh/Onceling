import 'package:cloud_functions/cloud_functions.dart';

/// Client edge of the pairing callables.
///
/// An interface so widget tests can substitute a fake without a live Functions
/// emulator — same shape as [AuthService].
abstract interface class PairingService {
  /// Returns the caller's pairing code, creating one server-side if needed.
  /// Idempotent: safe to call after every sign-in and from the pairing screen.
  Future<String> ensurePairingCode();

  /// Asks to pair with the owner of [code]. Returns the request id — and
  /// nothing else, deliberately (P2-23).
  Future<String> requestPairing(String code);

  /// Withdraws a pending request the caller sent (P2-24's Cancel).
  Future<void> cancelPairingRequest(String requestId);

  /// Separates the caller from their partner (**P2-36**).
  ///
  /// Phase 1 only: when this returns, both users are separated. Destroying the
  /// couple's data is a background sweep triggered by the status this writes.
  /// Idempotent — calling it while already unpaired succeeds.
  Future<void> unpair();

  /// Accepts or declines a request addressed to the caller (**P2-09b**).
  ///
  /// Accepting returns the new couple's id. Declining returns null — and
  /// writes `expired`, not `rejected`, so the sender is never told a person
  /// refused (**PI-05**).
  ///
  /// [timezone] is the accepting device's IANA zone (**P2-40**, **Q3**), which
  /// becomes the couple's shared day boundary. Null is fine and never fails the
  /// accept: the server validates it and falls back rather than rejecting a
  /// pairing over a field nothing reads until the next daily tick.
  Future<String?> respondToPairing(
    String requestId, {
    required bool accept,
    String? timezone,
  });
}

class FirebaseFunctionsPairingService implements PairingService {
  const FirebaseFunctionsPairingService(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<String> ensurePairingCode() async {
    final result = await _functions.httpsCallable('ensurePairingCode').call();
    return ((result.data as Map)['code'] as String?) ?? '';
  }

  @override
  Future<String> requestPairing(String code) async {
    final result = await _functions.httpsCallable('requestPairing').call({
      'code': code,
    });
    return ((result.data as Map)['requestId'] as String?) ?? '';
  }

  @override
  Future<void> cancelPairingRequest(String requestId) async {
    await _functions.httpsCallable('cancelPairingRequest').call({
      'requestId': requestId,
    });
  }

  @override
  Future<void> unpair() async {
    await _functions.httpsCallable('unpair').call();
  }

  @override
  Future<String?> respondToPairing(
    String requestId, {
    required bool accept,
    String? timezone,
  }) async {
    final result = await _functions.httpsCallable('respondToPairing').call({
      'requestId': requestId,
      'accept': accept,
      // Only sent on accept — a decline creates no couple to carry it.
      if (accept && timezone != null) 'timezone': timezone,
    });
    return (result.data as Map)['coupleId'] as String?;
  }
}

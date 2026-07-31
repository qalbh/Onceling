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
}

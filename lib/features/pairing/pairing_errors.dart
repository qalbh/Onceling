import 'package:cloud_functions/cloud_functions.dart';

/// Human copy for every rejection `requestPairing` can return.
///
/// Two rules govern this table:
///
/// 1. **`rate-limited` and `code-not-found` must read alike.** The callable
///    already spends budget before validating, so an exhausted caller gets the
///    same answer whether the code was real or not. Giving the two distinct
///    copy here would rebuild the enumeration oracle the server deleted.
/// 2. **`owner-already-paired` must read like `code-not-found`.** The server
///    returns the same message for both, because telling a stranger "that
///    person is already taken" confirms the code belongs to a real account.
String pairingErrorMessage(Object error) {
  final reason = error is FirebaseFunctionsException
      ? (error.details is Map
            ? (error.details as Map)['reason'] as String?
            : null)
      : null;

  return switch (reason) {
    'caller-already-paired' =>
      'You are already paired. Onceling is for two people only.',
    'self-pairing' =>
      'That is your own code. Share it with your person instead.',
    'request-already-pending' => 'You already asked. They will see it.',

    // The next three are deliberately the same sentence. See the note above.
    'code-not-found' || 'owner-already-paired' || 'rate-limited' =>
      "That code did not work. Check it and try again in a little while.",

    'code-malformed' => 'A code is six characters.',
    _ => 'Something went wrong. Try again.',
  };
}

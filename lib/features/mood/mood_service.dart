import 'package:cloud_functions/cloud_functions.dart';

/// Client edge of the `setMood` callable (**P2-12**).
///
/// A callable rather than a write because a mood lands in two places at once —
/// the ambient value on `couples/{id}` and a `status` item in the scrollback —
/// and `couples` denies every client write. The two halves go in one batch
/// server-side, so a mood cannot half-apply.
abstract interface class MoodService {
  Future<void> setMood({required String emoji, required String note});
}

class FirebaseFunctionsMoodService implements MoodService {
  const FirebaseFunctionsMoodService(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<void> setMood({required String emoji, required String note}) async {
    await _functions.httpsCallable('setMood').call({
      'emoji': emoji,
      'note': note,
    });
  }
}

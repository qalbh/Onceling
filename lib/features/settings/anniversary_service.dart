import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/providers.dart';

/// Client edge of the `setAnniversary` callable (**P2-39**).
///
/// An interface so the settings tests can substitute a fake — the same shape
/// as [PairingService], and for the same reason.
abstract interface class AnniversaryService {
  /// Sets the couple's anniversary to the calendar day of [date].
  ///
  /// Only the year/month/day are sent — as a `YYYY-MM-DD` key, not an
  /// instant — because an anniversary is a day on a wall calendar and the
  /// server resolves it against the COUPLE'S timezone, not this device's.
  ///
  /// Returns the milestone day this edit crossed, or null. The caller does
  /// not need to act on it — the milestone moment arrives through the gate —
  /// but it is useful signal for tests and logging.
  Future<int?> setAnniversary(DateTime date);
}

class FirebaseAnniversaryService implements AnniversaryService {
  const FirebaseAnniversaryService(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<int?> setAnniversary(DateTime date) async {
    final key =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final result = await _functions.httpsCallable('setAnniversary').call({
      'date': key,
    });
    return (result.data as Map)['milestone'] as int?;
  }
}

final anniversaryServiceProvider = Provider<AnniversaryService>(
  (ref) => FirebaseAnniversaryService(ref.watch(functionsProvider)),
);

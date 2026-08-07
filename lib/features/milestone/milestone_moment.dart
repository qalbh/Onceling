import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/providers.dart';
import '../pairing/couple_names.dart';

/// The milestone this partner has not yet seen full-screen, or null (**P3-03**).
///
/// **Deliberately NOT P2-26's transition detector, and the difference is the
/// point.** The pairing celebration watches a state change arrive, because one
/// partner causes it and the other's document changes underneath them — a
/// session that never saw the change has nothing to celebrate. A milestone has
/// no actor at all. Both partners are passive, so "did this session watch it
/// happen" is the wrong question: a couple crosses day 100 at their own
/// midnight, with both phones dark, and both people deserve the moment when
/// they next open the app — days later, cold start, whatever.
///
/// So the trigger is a comparison between two pieces of SERVER state, not an
/// observation of change:
///
/// - `couples/{id}.milestoneCelebrated` — the highest day the tick has fired,
///   written server-side, forgeable by nobody.
/// - `users/{uid}.milestoneSeen` — the highest day THIS partner has seen the
///   moment for, written by this client when they dismiss it.
///
/// `celebrated > seen` → show. Each partner carries their own `milestoneSeen`,
/// so each sees the moment exactly once, independently; a cold start after
/// dismissal compares equal and shows nothing. There is no session flag doing
/// the real work — the acknowledgement is durable state, which is what "once"
/// has to mean across reinstalls and second devices.
///
/// [_ackedThisSession] exists only to bridge the write's round trip: without
/// it, the moment would linger between the tap and the profile stream echoing
/// the new value back.
class MilestoneMomentNotifier extends Notifier<int?> {
  int _ackedThisSession = 0;

  @override
  int? build() {
    final celebrated =
        ref.watch(coupleProvider).valueOrNull?.milestoneCelebrated ?? 0;
    final seen = ref.watch(currentUserProvider).valueOrNull?.milestoneSeen ?? 0;

    if (celebrated <= seen || celebrated <= _ackedThisSession) return null;
    return celebrated;
  }

  /// The moment has been seen. Releases the gate and makes it durable.
  ///
  /// The write is fire-and-forget with a log on failure rather than an error
  /// surface: the SDK queues it offline, and the one consequence of a lost
  /// write is seeing the moment again next cold start — a nuisance, not a
  /// harm, and not worth an error dialog on a celebration.
  void acknowledge() {
    final day = state;
    if (day == null) return;
    _ackedThisSession = day;

    final uid = ref.read(currentUserProvider).valueOrNull?.uid;
    if (uid != null) {
      ref
          .read(firestoreProvider)
          .collection('users')
          .doc(uid)
          .update({'milestoneSeen': day})
          .catchError((Object error) {
            developer.log(
              'milestoneSeen write failed: $error',
              name: 'MilestoneMoment',
            );
          });
    }

    // Recompute: _ackedThisSession now suppresses this day locally.
    ref.invalidateSelf();
  }
}

final milestoneMomentProvider = NotifierProvider<MilestoneMomentNotifier, int?>(
  MilestoneMomentNotifier.new,
);

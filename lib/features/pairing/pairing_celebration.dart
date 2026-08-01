import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/providers.dart';
import '../auth/models/user_profile.dart';

/// Holds the couple id whose pairing moment (**P2-26**) has not been seen yet,
/// or null when there is nothing to show.
///
/// **Why a transition detector rather than a flag set by the Accept button.**
/// Only one of the two partners taps anything. A knows they just paired; B's
/// `coupleId` changes underneath them via the profile stream with no local
/// action at all. Watching the stream is the one mechanism that fires for both
/// sides, so neither is special-cased.
///
/// The distinction that makes "once and never again" work is *not* "is there a
/// coupleId" — it is "did this session watch a coupleId appear". A cold start
/// on an already-paired account sees a non-null coupleId in its very first
/// emission, never having seen an unpaired profile, so it shows nothing and
/// the gate routes straight to the feed.
class PairingCelebrationNotifier extends Notifier<String?> {
  /// True once a profile has been seen carrying no coupleId. Without this, a
  /// cold start would treat its first emission as an arrival.
  bool _sawUnpaired = false;

  /// The couple already celebrated, so a rebuild cannot replay the moment.
  String? _seen;

  @override
  String? build() {
    ref.listen(currentUserProvider, (_, next) => _observe(next.valueOrNull));
    // Seeds the flag only — deliberately NOT _observe.
    //
    // _observe writes `state`, and this runs inside build(), where the provider
    // is not yet initialised: a write here throws "Tried to read the state of
    // an uninitialized provider". It used to call _observe and was safe purely
    // because `_sawUnpaired` is false on the first pass, so the write branch
    // was unreachable. That was an accident of ordering, not a design, and it
    // broke the moment a debug print touched `state` at the top of _observe.
    _seedFromCurrent(ref.read(currentUserProvider).valueOrNull);
    return null;
  }

  /// The half of [_observe] that touches no state — safe to run during build.
  void _seedFromCurrent(UserProfile? profile) {
    if (profile != null && profile.coupleId == null) _sawUnpaired = true;
  }

  void _observe(UserProfile? profile) {
    // A missing document says nothing about pairing — it is the gap between
    // the account existing and its profile being written. Treating it as
    // "unpaired" would arm the celebration on every cold start.
    if (profile == null) return;

    final coupleId = profile.coupleId;
    if (coupleId == null) {
      _sawUnpaired = true;
      return;
    }
    if (_sawUnpaired && _seen != coupleId) state = coupleId;
  }

  /// Called when the moment has been shown. The gate moves to the feed as soon
  /// as this clears.
  void acknowledge() {
    _seen = state;
    state = null;
  }
}

final pairingCelebrationProvider =
    NotifierProvider<PairingCelebrationNotifier, String?>(
      PairingCelebrationNotifier.new,
    );

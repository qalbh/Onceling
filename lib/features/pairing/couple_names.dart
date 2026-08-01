import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/providers.dart';
import '../feed/models/sample_thread.dart';
import 'models/couple.dart';

/// Shown where a name is required but none is known.
///
/// Deliberately not a blank and not a crash: couples formed before **M-02**
/// carry no `memberNames`, and both simulator accounts are that case. There is
/// no migration by design — re-pairing regenerates the map.
const unknownMemberName = 'Your person';

/// The signed-in user's own display name, straight from their profile.
final myNameProvider = Provider<String>((ref) {
  final name = ref.watch(currentUserProvider).valueOrNull?.displayName.trim();
  return (name == null || name.isEmpty) ? 'You' : name;
});

/// The partner's display name, from the couple's denormalised `memberNames`.
///
/// Not read from their profile document: `users` is owner-only, and widening
/// it to "anyone paired with me" is the enumerable-directory surface the P2-09b
/// audit flagged. Denormalising onto a members-only document is the same trade
/// **P2-25** made for `fromDisplayName`.
final partnerNameProvider = Provider<String>((ref) {
  final couple = ref.watch(coupleProvider).valueOrNull;
  final myUid = ref.watch(currentUserProvider).valueOrNull?.uid;
  if (couple == null || myUid == null) return unknownMemberName;

  final partnerId = couple.partnerOf(myUid);
  if (partnerId == null) return unknownMemberName;

  final name = couple.memberNames[partnerId]?.trim();
  return (name == null || name.isEmpty)
      // Pre-M-02 couple, or a name the server could not resolve.
      ? unknownMemberName
      : name;
});

/// What the thread and settings call this pair.
///
/// `coupleName` is null on every real couple — nothing sets it yet — so the
/// fallback is what people actually see: both first names, in the order the
/// couple stores them. If the partner is unknown it degrades to the neutral
/// label rather than showing half a title.
final coupleTitleProvider = Provider<String>((ref) {
  final couple = ref.watch(coupleProvider).valueOrNull;
  final named = couple?.coupleName?.trim();
  if (named != null && named.isNotEmpty) return named;

  final partner = ref.watch(partnerNameProvider);
  if (partner == unknownMemberName) return unknownMemberName;
  return '${ref.watch(myNameProvider)} & $partner';
});

/// Resolves any uid to a display name, for surfaces that hold a uid rather
/// than a role — a feed item's `senderId`, say.
///
/// The `mockMembers` fallback keeps the sample thread readable while its items
/// are still mock data. **Delete the mock branch in P2-12**, together with
/// `sampleThread()`; it is here to stop the feed reading "Your person" for
/// every message, not because mock identity is wanted.
final memberNameResolverProvider = Provider<String Function(String)>((ref) {
  final couple = ref.watch(coupleProvider).valueOrNull;
  final myUid = ref.watch(currentUserProvider).valueOrNull?.uid;
  final myName = ref.watch(myNameProvider);

  return (String uid) {
    if (uid == myUid) return myName;
    final real = couple?.memberNames[uid]?.trim();
    if (real != null && real.isNotEmpty) return real;
    // P2-12: remove with the mock thread.
    return mockMembers[uid]?.name ?? unknownMemberName;
  };
});

/// First character of a resolved name, for avatar chips.
final memberInitialResolverProvider = Provider<String Function(String)>((ref) {
  final resolve = ref.watch(memberNameResolverProvider);
  return (String uid) {
    final name = resolve(uid);
    return name.isEmpty ? '?' : name.characters.first.toUpperCase();
  };
});

/// The couple document, or null when unpaired.
final coupleProvider = StreamProvider<Couple?>((ref) {
  final coupleId = ref.watch(currentUserProvider).valueOrNull?.coupleId;
  if (coupleId == null) return Stream<Couple?>.value(null);

  return ref
      .watch(firestoreProvider)
      .collection('couples')
      .doc(coupleId)
      .snapshots()
      .map(
        (snapshot) => snapshot.exists
            ? Couple.fromFirestore(snapshot.id, snapshot.data()!)
            : null,
      );
});

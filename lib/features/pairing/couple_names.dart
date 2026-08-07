import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/providers.dart';
import '../../common/time_format.dart';
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

/// Shown in place of the anniversary line when no date is known.
///
/// Same shape of answer as [unknownMemberName]: neutral and true, rather than
/// blank or a date the couple never chose. Every couple paired before **M-10**
/// is in this state, and there is no migration by design.
const unknownAnniversary = 'your shared space';

/// The line under the couple's name: `994 days · since 4 November 2023`.
///
/// Computed from the couple's `anniversaryDate`, which `respondToPairing`
/// defaults to the pairing date (**M-10**). It was hardcoded until then, on a
/// screen that had started showing real messages.
///
/// Reads the clock through [nowProvider] so a test asserting a day count can
/// pin it — otherwise the test would change its own answer overnight.
final anniversaryLineProvider = Provider<String>((ref) {
  final anniversary = ref.watch(coupleProvider).valueOrNull?.anniversaryDate;
  if (anniversary == null) return unknownAnniversary;

  final days = daysBetween(anniversary, ref.watch(nowProvider)());
  // Day zero is the day you paired, and "0 days" reads as an error rather than
  // as today. A negative count would mean a clock skew or a bad document;
  // neither is worth rendering.
  if (days < 1) return 'since ${formatCalendarDate(anniversary)}';
  return '$days day${days == 1 ? '' : 's'} · '
      'since ${formatCalendarDate(anniversary)}';
});

/// The anniversary as a settings row shows it — the date alone, no day count.
///
/// A couple with no date gets a call to action, not a dead label (**P2-39**):
/// "Not set" described a fact nobody could act on, and every pre-M-10 couple
/// sat behind it permanently. The row is now the edit path, so the empty
/// state's job is to say so.
final anniversaryLabelProvider = Provider<String>((ref) {
  final anniversary = ref.watch(coupleProvider).valueOrNull?.anniversaryDate;
  return anniversary == null
      ? 'Set your day one'
      : formatCalendarDate(anniversary);
});

/// The streak as the header and settings show it (**M-06**, **P3-02**).
///
/// Was a hardcoded `47` in two places. [faded] carries **Q2**'s decision that a
/// broken streak keeps its number and loses its colour, rather than dropping to
/// zero and erasing the history for having been interrupted.
typedef StreakDisplay = ({int count, bool faded});

final streakProvider = Provider<StreakDisplay>((ref) {
  final couple = ref.watch(coupleProvider).valueOrNull;
  return (
    count: couple?.streakCount ?? 0,
    faded: couple?.isStreakFaded ?? false,
  );
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
/// The `mockMembers` fallback that used to sit at the end of this is gone with
/// the sample thread (**P2-12**). Every uid the feed can now show belongs to
/// one of the couple's two members, so a name that does not resolve means a
/// pre-**M-02** couple with no `memberNames`, and the neutral label is the
/// honest answer rather than a stand-in identity.
final memberNameResolverProvider = Provider<String Function(String)>((ref) {
  final couple = ref.watch(coupleProvider).valueOrNull;
  final myUid = ref.watch(currentUserProvider).valueOrNull?.uid;
  final myName = ref.watch(myNameProvider);

  return (String uid) {
    if (uid == myUid) return myName;
    final real = couple?.memberNames[uid]?.trim();
    return (real == null || real.isEmpty) ? unknownMemberName : real;
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

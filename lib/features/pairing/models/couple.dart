/// A row of `couples/{coupleId}`.
///
/// Written only by the callables; the client never writes this collection, and
/// Security Rules let only its two members read it.
class Couple {
  const Couple({
    required this.id,
    required this.memberIds,
    required this.memberNames,
    this.coupleName,
    this.anniversaryDate,
    this.streakCount = 0,
    this.moodEmoji,
    this.moodText,
    this.moodBy,
    this.moodUpdatedAt,
  });

  final String id;
  final List<String> memberIds;

  /// uid → display name, denormalised by `respondToPairing` (**M-02**).
  ///
  /// Empty for couples formed before that landed. Callers must cope: see
  /// `partnerNameProvider`, which falls back rather than showing a blank.
  ///
  /// A snapshot from pairing time — a later rename does not propagate. See the
  /// debt entry in STATUS.
  final Map<String, String> memberNames;

  /// Null until the pair names themselves; nothing sets it yet.
  final String? coupleName;

  /// The date the couple counts from (**M-10**).
  ///
  /// Defaulted to the pairing date by `respondToPairing` — the owner's
  /// decision, taken because a couple joining today has a real anniversary the
  /// app cannot know, and asking during pairing adds friction to the flow
  /// brief §11 calls the most important metric.
  ///
  /// **Null on every couple paired before that landed.** No migration by
  /// design, exactly as with [memberNames]; callers degrade to a neutral line
  /// rather than showing a blank or a date that is not true. **P2-39** adds
  /// the settings edit path.
  final DateTime? anniversaryDate;

  final int streakCount;

  /// The current ambient mood, written by the `setMood` callable (**P2-12**).
  ///
  /// The live value, distinct from the `status` items in the thread: those are
  /// the scrollback, this is what is true now. Null until someone sets one.
  final String? moodEmoji;
  final String? moodText;

  /// Whose mood it is. Both people set moods into the same couple document,
  /// so without this the ambient line cannot say who it belongs to.
  final String? moodBy;
  final DateTime? moodUpdatedAt;

  /// The other member, or null on a malformed couple.
  String? partnerOf(String uid) {
    for (final member in memberIds) {
      if (member != uid) return member;
    }
    return null;
  }

  factory Couple.fromFirestore(String id, Map<String, dynamic> data) {
    return Couple(
      id: id,
      memberIds:
          (data['memberIds'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      memberNames:
          (data['memberNames'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ) ??
          const {},
      coupleName: data['coupleName'] as String?,
      anniversaryDate: _readTime(data['anniversaryDate']),
      streakCount: (data['streakCount'] as num?)?.toInt() ?? 0,
      moodEmoji: data['moodEmoji'] as String?,
      moodText: data['moodText'] as String?,
      moodBy: data['moodBy'] as String?,
      moodUpdatedAt: _readTime(data['moodUpdatedAt']),
    );
  }
}

/// Accepts a `DateTime` or a Firestore `Timestamp`, like the feed mapper's own.
DateTime? _readTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return (value as dynamic).toDate() as DateTime;
}

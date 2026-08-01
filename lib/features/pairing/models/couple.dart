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
    this.streakCount = 0,
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

  final int streakCount;

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
      streakCount: (data['streakCount'] as num?)?.toInt() ?? 0,
    );
  }
}

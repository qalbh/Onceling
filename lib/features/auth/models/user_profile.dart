/// The eight quick-reaction emoji a new account starts with — the same set the
/// feed's tray offers today.
const defaultFavoriteEmojis = <String>[
  '❤️',
  '😂',
  '🥹',
  '🔥',
  '🫶',
  '🌙',
  '🧋',
  '🐈',
];

/// A row of `users/{uid}` (brief §9).
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.favoriteEmojis,
    this.coupleId,
    this.avatarUrl,
    this.accentColor,
    this.pairingCode,
    this.createdAt,
  });

  final String uid;
  final String displayName;
  final String? avatarUrl;

  /// Null until paired. **Never written by this client**: it is set only by
  /// **P2-09b**'s transaction and cleared only by unpair, and Security Rules
  /// reject any client write that changes it in either direction.
  final String? coupleId;

  final List<String> favoriteEmojis;
  final String? accentColor;

  /// Six characters, claimed and written only by the `ensurePairingCode`
  /// callable. Null until the first successful call; deleted by P2-09b when
  /// the pair forms. The client never writes this — rules reject it.
  final String? pairingCode;

  /// Null for the moment between a local write and the server timestamp
  /// resolving — `serverTimestamp()` reads back as null in the pending snapshot.
  final DateTime? createdAt;

  bool get isPaired => coupleId != null;

  factory UserProfile.fromFirestore(String uid, Map<String, dynamic> data) {
    return UserProfile(
      uid: uid,
      displayName: data['displayName'] as String? ?? '',
      avatarUrl: data['avatarUrl'] as String?,
      coupleId: data['coupleId'] as String?,
      favoriteEmojis:
          (data['favoriteEmojis'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      accentColor: data['accentColor'] as String?,
      pairingCode: data['pairingCode'] as String?,
      // Duck-typed for the same reason as the feed mapper: a pending write has
      // no Timestamp yet. See P2-22.
      createdAt: switch (data['createdAt']) {
        null => null,
        final DateTime value => value,
        final Object value => (value as dynamic).toDate() as DateTime,
      },
    );
  }

  /// The document written on first sign-in.
  ///
  /// `coupleId` is written exactly once, as null, and never touched again by
  /// the client.
  static Map<String, dynamic> initialDocument({
    required String displayName,
    required Object createdAt,
  }) {
    return <String, dynamic>{
      'displayName': displayName,
      'avatarUrl': null,
      'coupleId': null,
      'favoriteEmojis': defaultFavoriteEmojis,
      'accentColor': null,
      'createdAt': createdAt,
    };
  }
}

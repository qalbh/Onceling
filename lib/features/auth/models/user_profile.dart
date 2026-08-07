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
    this.onboardingSeenAt,
    this.milestoneSeen = 0,
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

  /// When the §10 honesty disclosure was shown (**PI-02**). Null means it has
  /// not been. Written only by `markOnboardingSeen`, set-once and
  /// server-stamped — the record that a required disclosure was made should
  /// not be authorable by the client it was made to.
  final DateTime? onboardingSeenAt;

  /// The highest milestone day THIS partner has seen the full-screen moment
  /// for (**P3-03**). Written by this client on dismissal — each partner keeps
  /// their own, which is what makes the moment once-per-partner rather than
  /// once-per-couple.
  final int milestoneSeen;

  bool get isPaired => coupleId != null;

  /// The gate's question: has this person met the disclosure yet?
  bool get hasSeenOnboarding => onboardingSeenAt != null;

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
      milestoneSeen: (data['milestoneSeen'] as num?)?.toInt() ?? 0,
      // Duck-typed for the same reason as the feed mapper: a pending write has
      // no Timestamp yet. See P2-22.
      createdAt: switch (data['createdAt']) {
        null => null,
        final DateTime value => value,
        final Object value => (value as dynamic).toDate() as DateTime,
      },
      onboardingSeenAt: switch (data['onboardingSeenAt']) {
        null => null,
        final DateTime value => value,
        final Object value => (value as dynamic).toDate() as DateTime,
      },
    );
  }
}

/// How long the recipient gets with a secret once they open it.
enum SecretDuration {
  tenSeconds('10 seconds', Duration(seconds: 10)),
  thirtySeconds('30 seconds', Duration(seconds: 30)),
  untilClosed('until they close it', null);

  const SecretDuration(this.label, this.window);

  final String label;
  final Duration? window;

  /// Wire form for `revealDurationSeconds`. Null means "until they close it".
  int? get seconds => window?.inSeconds;

  /// Short form used on the sent-secret bubble, e.g. "they get 30s with it".
  String get shortLabel => switch (this) {
    tenSeconds => 'they get 10s with it',
    thirtySeconds => 'they get 30s with it',
    untilClosed => 'until they close it',
  };
}

/// Whether a secret is still sealed or has been spent.
///
/// The body never lives here — it sits in `secretBodies/{itemId}` so a Function
/// can hard delete it (**P3-01**) while this tombstone survives.
enum SecretState { sealed, opened }

sealed class FeedItem {
  const FeedItem({
    required this.id,
    required this.senderId,
    required this.createdAt,
    this.reactions = const {},
  });

  /// Firestore document id. Locally-composed items carry a client-side id until
  /// the write lands.
  final String id;

  /// Author's uid. The feed decides sent-vs-received by comparing this against
  /// the signed-in user, which is why there is no `Person` here any more.
  final String senderId;

  final DateTime createdAt;

  /// uid → emoji. Brief §9 requires plural reactions on every item type.
  final Map<String, String> reactions;
}

/// A plain written message.
class TextMessage extends FeedItem {
  const TextMessage({
    required super.id,
    required super.senderId,
    required super.createdAt,
    required this.text,
    super.reactions,
  });

  final String text;

  @override
  bool operator ==(Object other) =>
      other is TextMessage &&
      other.id == id &&
      other.senderId == senderId &&
      other.createdAt == createdAt &&
      other.text == text &&
      _mapEquals(other.reactions, reactions);

  @override
  int get hashCode => Object.hash(id, senderId, createdAt, text);
}

/// A photo with an optional caption underneath.
class PhotoMessage extends FeedItem {
  const PhotoMessage({
    required super.id,
    required super.senderId,
    required super.createdAt,
    this.mediaUrl,
    this.caption,
    super.reactions,
  });

  /// Cloud Storage download URL. Null while the upload is still in flight.
  final String? mediaUrl;
  final String? caption;

  @override
  bool operator ==(Object other) =>
      other is PhotoMessage &&
      other.id == id &&
      other.senderId == senderId &&
      other.createdAt == createdAt &&
      other.mediaUrl == mediaUrl &&
      other.caption == caption &&
      _mapEquals(other.reactions, reactions);

  @override
  int get hashCode => Object.hash(id, senderId, createdAt, mediaUrl, caption);
}

/// A single emoji sent large, optionally tapped repeatedly ("×14").
class EmojiMessage extends FeedItem {
  const EmojiMessage({
    required super.id,
    required super.senderId,
    required super.createdAt,
    required this.emoji,
    this.count = 1,
    super.reactions,
  });

  final String emoji;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is EmojiMessage &&
      other.id == id &&
      other.senderId == senderId &&
      other.createdAt == createdAt &&
      other.emoji == emoji &&
      other.count == count &&
      _mapEquals(other.reactions, reactions);

  @override
  int get hashCode => Object.hash(id, senderId, createdAt, emoji, count);
}

/// Ambient centred line, e.g. "is heads down till four".
///
/// A mood update writes twice: the live value onto `couples/{id}`, and this
/// scrollback record into `items/`.
class StatusNote extends FeedItem {
  const StatusNote({
    required super.id,
    required super.senderId,
    required super.createdAt,
    required this.text,
    this.icon,
    super.reactions,
  });

  final String text;
  final String? icon;

  @override
  bool operator ==(Object other) =>
      other is StatusNote &&
      other.id == id &&
      other.senderId == senderId &&
      other.createdAt == createdAt &&
      other.text == text &&
      other.icon == icon &&
      _mapEquals(other.reactions, reactions);

  @override
  int get hashCode => Object.hash(id, senderId, createdAt, text, icon);
}

/// The tombstone for a sealed message.
///
/// Carries no body by design: the content lives in `secretBodies/{itemId}` so
/// deleting it is a server-side operation (**P3-01**) that leaves this record
/// intact. There is deliberately no `markOpened()` — a client that flips its own
/// copy to opened has not opened anything.
class SecretMessage extends FeedItem {
  const SecretMessage({
    required super.id,
    required super.senderId,
    required super.createdAt,
    required this.duration,
    this.secretState = SecretState.sealed,
    this.openedAt,
    this.heldFullCountdown = false,
    super.reactions,
  });

  final SecretDuration duration;
  final SecretState secretState;

  /// When the recipient opened it. Null while sealed.
  final DateTime? openedAt;

  /// Whether they stayed with it until the countdown emptied.
  final bool heldFullCountdown;

  bool get isOpened => secretState == SecretState.opened;

  @override
  bool operator ==(Object other) =>
      other is SecretMessage &&
      other.id == id &&
      other.senderId == senderId &&
      other.createdAt == createdAt &&
      other.duration == duration &&
      other.secretState == secretState &&
      other.openedAt == openedAt &&
      other.heldFullCountdown == heldFullCountdown &&
      _mapEquals(other.reactions, reactions);

  @override
  int get hashCode => Object.hash(
    id,
    senderId,
    createdAt,
    duration,
    secretState,
    openedAt,
    heldFullCountdown,
  );
}

/// Shallow map equality. Avoids a `package:collection` import for one use.
bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

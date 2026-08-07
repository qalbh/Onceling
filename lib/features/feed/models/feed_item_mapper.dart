import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'feed_item.dart';

/// Thrown when a document's `type` is absent or not one of the five known
/// values. Never silently defaulted: an unrecognised type means the client is
/// older than the data, and rendering it as a text message would quietly lose
/// whatever it actually was.
/// A `secretState` this build does not know.
///
/// Throws rather than defaulting, matching [UnknownFeedItemTypeException]. The
/// state decides whether a body is readable, so guessing is worse than
/// failing: silently reading an unknown state as `sealed` would treat an
/// expired reveal as a fresh one.
///
/// Deliberately unlike the unknown-*duration* fallback, which degrades because
/// a new duration option is additive and harmless. A new state is not.
class UnknownSecretStateException implements Exception {
  const UnknownSecretStateException({
    required this.itemId,
    required this.state,
  });

  final String itemId;
  final Object? state;

  @override
  String toString() =>
      'UnknownSecretStateException: item "$itemId" has secretState "$state", '
      'expected one of sealed, opening, opened';
}

class UnknownFeedItemTypeException implements Exception {
  const UnknownFeedItemTypeException({
    required this.itemId,
    required this.type,
  });

  final String itemId;
  final Object? type;

  @override
  String toString() =>
      'UnknownFeedItemTypeException: item "$itemId" has type "$type", '
      'expected one of text, photo, emoji, status, secret';
}

/// Wire values for `type`. Kept next to the mapper because nothing else should
/// need to know how an item is spelled on the wire.
const _typeText = 'text';
const _typePhoto = 'photo';
const _typeEmoji = 'emoji';
const _typeStatus = 'status';
const _typeSecret = 'secret';
const _typeMilestone = 'milestone';

const _stateSealed = 'sealed';
const _stateOpening = 'opening';
const _stateOpened = 'opened';

/// Builds a [FeedItem] from a Firestore document.
///
/// [id] is the document id — it is the key, not a field, so it arrives
/// separately and is never written back by [toFirestore].
FeedItem fromFirestore(String id, Map<String, dynamic> data) {
  // An unresolved `createdAt` is our own optimistic local echo: the snapshot
  // Firestore emits before the server has acked the write, where the pending
  // `serverTimestamp()` still reads as null. `now()` is the same estimate the
  // native SDKs' `ServerTimestampBehavior.estimate` supplies, and the real
  // value arrives a moment later. Not an error case — every message you send
  // passes through it.
  final createdAt = _readTime(data['createdAt']) ?? DateTime.now();
  final senderId = data['senderId'] as String? ?? '';
  final reactions = _readReactions(data['reactions']);

  return switch (data['type']) {
    _typeText => TextMessage(
      id: id,
      senderId: senderId,
      createdAt: createdAt,
      text: data['body'] as String? ?? '',
      reactions: reactions,
    ),
    _typePhoto => PhotoMessage(
      id: id,
      senderId: senderId,
      createdAt: createdAt,
      mediaUrl: data['mediaUrl'] as String?,
      caption: data['caption'] as String?,
      reactions: reactions,
    ),
    _typeEmoji => EmojiMessage(
      id: id,
      senderId: senderId,
      createdAt: createdAt,
      emoji: data['emoji'] as String? ?? '',
      count: (data['count'] as num?)?.toInt() ?? 1,
      reactions: reactions,
    ),
    _typeStatus => StatusNote(
      id: id,
      senderId: senderId,
      createdAt: createdAt,
      text: data['body'] as String? ?? '',
      icon: data['emoji'] as String?,
      reactions: reactions,
    ),
    _typeMilestone => MilestoneMessage(
      id: id,
      createdAt: createdAt,
      day: (data['day'] as num?)?.toInt() ?? 0,
      reactions: reactions,
    ),
    _typeSecret => SecretMessage(
      id: id,
      senderId: senderId,
      createdAt: createdAt,
      duration: _readDuration(id, data['revealDurationSeconds']),
      secretState: _readSecretState(id, data['secretState']),
      openingStartedAt: _readTime(data['openingStartedAt']),
      openedAt: _readTime(data['openedAt']),
      heldFullCountdown: data['heldFullCountdown'] as bool? ?? false,
      reactions: reactions,
    ),
    final unknown => throw UnknownFeedItemTypeException(
      itemId: id,
      type: unknown,
    ),
  };
}

/// Flattens a [FeedItem] into a Firestore document.
///
/// Omits `id` (it is the document key) and `coupleId` (the writer supplies it —
/// the model has no couple to report, and inventing one here would let a
/// mis-scoped write past Security Rules).
Map<String, dynamic> toFirestore(FeedItem item) {
  final common = <String, dynamic>{
    'senderId': item.senderId,
    'createdAt': item.createdAt,
    'reactions': Map<String, String>.from(item.reactions),
  };

  return switch (item) {
    TextMessage(:final text) => {...common, 'type': _typeText, 'body': text},
    PhotoMessage(:final mediaUrl, :final caption) => {
      ...common,
      'type': _typePhoto,
      'mediaUrl': mediaUrl,
      'caption': caption,
    },
    EmojiMessage(:final emoji, :final count) => {
      ...common,
      'type': _typeEmoji,
      'emoji': emoji,
      'count': count,
    },
    StatusNote(:final text, :final icon) => {
      ...common,
      'type': _typeStatus,
      'body': text,
      'emoji': icon,
    },
    // Round-trip completeness only: the client never writes one of these. The
    // real document is authored in TypeScript by the tick, without a senderId
    // at all; the '' this carries is [MilestoneMessage]'s no-author sentinel
    // and must never reach a write path.
    MilestoneMessage(:final day) => {
      ...common,
      'type': _typeMilestone,
      'day': day,
    },
    SecretMessage(
      :final duration,
      :final secretState,
      :final openingStartedAt,
      :final openedAt,
      :final heldFullCountdown,
    ) =>
      {
        ...common,
        'type': _typeSecret,
        'secretState': switch (secretState) {
          SecretState.sealed => _stateSealed,
          SecretState.opening => _stateOpening,
          SecretState.opened => _stateOpened,
        },
        'openingStartedAt': openingStartedAt,
        'revealDurationSeconds': duration.seconds,
        'openedAt': openedAt,
        'heldFullCountdown': heldFullCountdown,
      },
  };
}

/// The document for a **new** item, ready to hand to Firestore (**P2-12**).
///
/// Not the same thing as [toFirestore], and the two differences are both
/// forced by the P2-10 rules rather than by taste:
///
/// 1. **`createdAt` becomes a server timestamp.** `allow create` requires
///    `createdAt == request.time`, so a client-chosen time is rejected outright.
///    The model's own `createdAt` is a placeholder the writer never keeps.
/// 2. **Null-valued keys are dropped.** Rules validate `keys().hasOnly(...)`
///    per type, and in Firestore an explicit null is a *present* key. Writing
///    `openingStartedAt: null` on a secret would therefore be rejected — that
///    field belongs to **P3-01**'s `sealed -> opening` transition and is not in
///    the permitted create set at all. Same for `revealDurationSeconds` on an
///    `untilClosed` secret, which must be absent rather than null.
///
/// Reading is unaffected: [fromFirestore] treats an absent key and a null one
/// identically for every optional field, so a stripped document round-trips.
Map<String, dynamic> itemCreatePayload(
  FeedItem item, {
  required String coupleId,
}) {
  return {
    for (final entry in toFirestore(item).entries)
      if (entry.value != null) entry.key: entry.value,
    'coupleId': coupleId,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

/// The `secretBodies/{itemId}` document that accompanies a secret.
///
/// All four fields are required by the rules, and three of them are recorded
/// on **P2-12** as load-bearing: `coupleId` is how **P2-36**'s sweep finds a
/// body whose item is already gone, `senderId` binds creation to the sender
/// without a `get()` on an item that may not be committed yet, and `body` is
/// the payload. `createdAt` is the same server-time check as above.
Map<String, dynamic> secretBodyPayload({
  required String coupleId,
  required String senderId,
  required String body,
}) {
  return {
    'coupleId': coupleId,
    'senderId': senderId,
    'body': body,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

/// Accepts a `DateTime` or a Firestore `Timestamp`.
///
/// Writes go out as `DateTime`, which the SDK stores as a `Timestamp` natively;
/// reads come back as `Timestamp`.
///
// TODO(P2-07): replace the duck-type with a real `Timestamp` cast once
// `cloud_firestore` is a dependency. Until then this is dynamic dispatch on
// `toDate()`, so a value that is neither a DateTime nor a Timestamp fails at
// runtime instead of being caught by the analyzer.
DateTime? _readTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return (value as dynamic).toDate() as DateTime;
}

Map<String, String> _readReactions(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      entry.key.toString(): entry.value.toString(),
  };
}

/// Reveal windows this build offers, shortest first. Iteration order matters:
/// see the tie-break in [_readDuration].
const _knownDurations = <int, SecretDuration>{
  10: SecretDuration.tenSeconds,
  30: SecretDuration.thirtySeconds,
};

/// Parses `secretState`, throwing on anything unrecognised.
SecretState _readSecretState(String id, Object? raw) => switch (raw) {
  _stateSealed => SecretState.sealed,
  _stateOpening => SecretState.opening,
  _stateOpened => SecretState.opened,
  final unknown => throw UnknownSecretStateException(
    itemId: id,
    state: unknown,
  ),
};

/// Never throws.
///
/// Unlike an unknown `type` — which means a corrupt document — an unknown
/// window means a *newer* client wrote one this build does not offer yet. If a
/// 60s option ships later, throwing here would crash every old client on new
/// data, so an unrecognised value falls back to the nearest known window.
///
/// Ties resolve to the shorter window: showing a secret for longer than the
/// sender chose is the worse of the two failures.
SecretDuration _readDuration(String itemId, Object? value) {
  if (value == null) return SecretDuration.untilClosed;

  if (value is! num) {
    developer.log(
      'item "$itemId" has non-numeric revealDurationSeconds "$value"; '
      'falling back to untilClosed',
      name: 'FeedItemMapper',
    );
    return SecretDuration.untilClosed;
  }

  final seconds = value.toInt();
  final known = _knownDurations[seconds];
  if (known != null) return known;

  var nearest = SecretDuration.untilClosed;
  var smallestGap = -1;
  for (final entry in _knownDurations.entries) {
    final gap = (entry.key - seconds).abs();
    // Strict `<` keeps the first (shortest) window on a tie.
    if (smallestGap == -1 || gap < smallestGap) {
      smallestGap = gap;
      nearest = entry.value;
    }
  }

  developer.log(
    'item "$itemId" has unrecognised revealDurationSeconds "$seconds"; '
    'falling back to ${nearest.name}',
    name: 'FeedItemMapper',
  );
  return nearest;
}

import 'package:cloud_firestore/cloud_firestore.dart';

import 'models/feed_item.dart';
import 'models/feed_item_mapper.dart';

/// Client edge of the `items` collection (**P2-12**).
///
/// An interface for the same reason `PairingService` is one: widget tests need
/// to assert *what* the screen asked for without a live Firestore.
///
/// Every method takes `coupleId` and `senderId` explicitly rather than reading
/// them from a provider. The rules check both — `senderId == request.auth.uid`
/// and `coupleId == ` the caller's own — so a write that guesses either is a
/// permission error, and the guessing is better done at one call site than
/// buried here.
abstract interface class FeedService {
  Future<void> sendText({
    required String coupleId,
    required String senderId,
    required String text,
  });

  /// One tap, one item. The mock thread aggregated repeats into `count: 14`;
  /// real ones cannot, because `allow update` is reactions-only and nothing
  /// server-side aggregates yet. `count` stays on the model and in the rules
  /// so an aggregate can arrive later without a migration.
  Future<void> sendEmoji({
    required String coupleId,
    required String senderId,
    required String emoji,
  });

  /// Writes the tombstone and its body **in one batch**.
  ///
  /// Not two awaited writes: a failure between them would leave either a
  /// secret with no body to reveal, or an unreachable body that **P2-36**'s
  /// sweep would have to find by `coupleId` alone. The batch makes both
  /// impossible.
  Future<void> sendSecret({
    required String coupleId,
    required String senderId,
    required String text,
    required SecretDuration duration,
  });

  /// Adds or replaces the caller's own reaction on [itemId].
  ///
  /// A single-key update, because the rules permit exactly that: the document
  /// diff may touch only `reactions`, and within it only `request.auth.uid`.
  Future<void> react({
    required String itemId,
    required String senderId,
    required String emoji,
  });
}

class FirestoreFeedService implements FeedService {
  const FirestoreFeedService(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _items =>
      _db.collection('items');

  /// The id every locally-built [FeedItem] carries before Firestore assigns
  /// one. Never written — [toFirestore] omits the id, it is the document key.
  static const _pendingId = 'pending';

  @override
  Future<void> sendText({
    required String coupleId,
    required String senderId,
    required String text,
  }) {
    return _items.add(
      itemCreatePayload(
        TextMessage(
          id: _pendingId,
          senderId: senderId,
          createdAt: DateTime.now(),
          text: text,
        ),
        coupleId: coupleId,
      ),
    );
  }

  @override
  Future<void> sendEmoji({
    required String coupleId,
    required String senderId,
    required String emoji,
  }) {
    return _items.add(
      itemCreatePayload(
        EmojiMessage(
          id: _pendingId,
          senderId: senderId,
          createdAt: DateTime.now(),
          emoji: emoji,
        ),
        coupleId: coupleId,
      ),
    );
  }

  @override
  Future<void> sendSecret({
    required String coupleId,
    required String senderId,
    required String text,
    required SecretDuration duration,
  }) {
    // The id is minted here rather than by `add()`, because the body document
    // is keyed by it and both writes go in the same batch.
    final itemRef = _items.doc();

    return (_db.batch()
          ..set(
            itemRef,
            itemCreatePayload(
              SecretMessage(
                id: itemRef.id,
                senderId: senderId,
                createdAt: DateTime.now(),
                duration: duration,
              ),
              coupleId: coupleId,
            ),
          )
          ..set(
            _db.collection('secretBodies').doc(itemRef.id),
            secretBodyPayload(
              coupleId: coupleId,
              senderId: senderId,
              body: text,
            ),
          ))
        .commit();
  }

  @override
  Future<void> react({
    required String itemId,
    required String senderId,
    required String emoji,
  }) {
    return _items.doc(itemId).update({'reactions.$senderId': emoji});
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/providers.dart';
import 'feed_service.dart';
import 'models/feed_item.dart';
import 'models/feed_item_mapper.dart';

/// How many items each page of the thread carries.
///
/// Thirty is roughly three phone screens of bubbles at default text size —
/// enough that the first page fills the view and survives a little scrolling
/// before the next is needed, small enough that the opening payload of a
/// conversation people keep for years stays small.
const feedPageSize = 30;

/// One page of the thread, plus whether there is more behind it.
class FeedPage {
  const FeedPage({required this.items, required this.hasMore});

  static const empty = FeedPage(items: [], hasMore: false);

  /// **Newest first**, matching the query. The list renders reversed, so index
  /// 0 is the bubble at the bottom of the screen.
  final List<FeedItem> items;

  /// True when the query filled its window exactly, which is the only signal
  /// Firestore gives without a second read. It can be a false positive on a
  /// thread whose length is an exact multiple of [feedPageSize]: the next page
  /// then comes back empty and this goes false. Cheaper than a count query,
  /// and the cost of being wrong is one wasted page load.
  final bool hasMore;
}

/// How many items the live query currently asks for.
///
/// Pagination is **one growing window**, not a live page plus static older
/// pages. Every item on screen therefore stays live: a reaction landing on a
/// message from last week updates in place, which is the whole point of
/// reactions on a two-person thread.
///
/// What that costs: growing the limit re-subscribes, and Firestore re-delivers
/// the whole window rather than just the new tail. Reading N pages costs
/// `30 + 60 + 90 + ...` document reads — quadratic in pages, not linear. At
/// this page size a couple would have to scroll back through roughly a
/// thousand messages in one sitting before that runs into four figures, so it
/// is the right trade here and the wrong one for a feed with many
/// participants or long scrollback sessions. Revisit by splitting into a live
/// head plus `startAfter` pages if it ever bites.
class FeedWindow extends Notifier<int> {
  @override
  int build() => feedPageSize;

  void loadMore() => state += feedPageSize;
}

final feedWindowProvider = NotifierProvider<FeedWindow, int>(FeedWindow.new);

/// Live thread for the signed-in user's couple (**P2-12**).
///
/// The `coupleId` filter is load-bearing, not decoration: `allow list` grants
/// the query only where it provably stays inside the caller's own couple, so
/// dropping the `where` does not return more rows — it returns
/// permission-denied for the whole query.
///
/// A signed-in user with no `coupleId` emits an empty page rather than
/// querying. The router gate already keeps them on the pairing screen, but a
/// provider that assumed the gate would fire an unscoped query the instant the
/// gate was ever wrong.
final feedProvider = StreamProvider<FeedPage>((ref) {
  final coupleId = ref.watch(currentUserProvider).valueOrNull?.coupleId;
  if (coupleId == null) return Stream.value(FeedPage.empty);

  final limit = ref.watch(feedWindowProvider);

  return ref
      .watch(firestoreProvider)
      .collection('items')
      .where('coupleId', isEqualTo: coupleId)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((snapshot) {
        final items = snapshot.docs
            .map((doc) => fromFirestore(doc.id, doc.data()))
            .toList();

        // Re-sorted client-side because a message you have just sent carries an
        // unresolved server timestamp, which orders as null until the ack.
        // `fromFirestore` estimates it as `now()`, so sorting here puts your own
        // message at the top where you expect it instead of at the far end of
        // the thread for the round trip.
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return FeedPage(items: items, hasMore: snapshot.docs.length == limit);
      });
});

/// Client edge of the item writes.
final feedServiceProvider = Provider<FeedService>(
  (ref) => FirestoreFeedService(ref.watch(firestoreProvider)),
);

/// Convenience for the write path, which needs both halves of the rule check.
///
/// Null when either is missing — signed out, or a profile that has not
/// resolved. Callers must not write in that state; there is nothing valid to
/// write as.
({String coupleId, String senderId})? feedWriteIdentity(WidgetRef ref) {
  final profile = ref.read(currentUserProvider).valueOrNull;
  final coupleId = profile?.coupleId;
  if (profile == null || coupleId == null) return null;
  return (coupleId: coupleId, senderId: profile.uid);
}

/// Kept out of [feedProvider] so a retry re-runs the query without disturbing
/// how far the reader had paged back.
void retryFeed(WidgetRef ref) => ref.invalidate(feedProvider);

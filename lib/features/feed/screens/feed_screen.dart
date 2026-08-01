import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/app_router.dart';
import '../../../common/app_toast.dart';
import '../../../common/providers.dart';
import '../../../theme/theme_colors.dart';
import '../../compose/compose_sheet.dart';
import '../../mood/mood_sheet.dart';
import '../../pairing/couple_names.dart';
import '../../secret/screens/secret_reveal_screen.dart';
import '../feed_emoji.dart';
import '../feed_providers.dart';
import '../models/feed_item.dart';
import '../widgets/emoji_burst.dart';
import '../widgets/emoji_tray.dart';
import '../widgets/feed_header.dart';
import '../widgets/feed_item_view.dart';
import '../widgets/feed_states.dart';
import '../widgets/reaction_tray.dart';

/// The shared thread, rendered from the signed-in user's side.
///
/// The viewer is whoever is signed in — never a parameter, never local state.
/// A long-press used to swap perspective, which was how both mock layouts were
/// reachable before auth existed; it let a real user become their partner, so
/// it is gone. Seeing the other side now requires being the other person.
///
/// Since **P2-12** the thread is a live Firestore listener rather than local
/// state. Nothing here mutates a list: a send is a write, and the item appears
/// because the listener saw it — on both devices, by the same route.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _burstKey = GlobalKey<EmojiBurstLayerState>();
  final _scrollController = ScrollController();

  /// The signed-in reader. Empty only in the instant before the profile
  /// stream resolves, which the gate normally prevents from being visible.
  String get _viewerId => ref.read(currentUserProvider).valueOrNull?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Grows the window when the reader nears the old end of the thread.
  ///
  /// The list is `reverse: true`, so `maxScrollExtent` is the *oldest*
  /// message, not the newest — scrolling up is scrolling towards the limit.
  /// The 400px margin starts the next page before the reader hits the end, so
  /// paging is invisible when it keeps up and merely slow when it does not.
  void _maybeLoadMore() {
    // The listener can fire while the tree is being torn down — pushing the
    // reveal route re-measures the list. `ref` on a deactivated element throws
    // "looking up a deactivated widget's ancestor", so check before reading.
    if (!mounted) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 400) return;
    if (ref.read(feedProvider).valueOrNull?.hasMore != true) return;
    ref.read(feedWindowProvider.notifier).loadMore();
  }

  /// Runs [write] and reports a failure rather than swallowing it.
  ///
  /// Every write here can be refused — rules deny a mis-scoped item, and the
  /// network can drop. A send that silently does nothing is the worst of the
  /// available failures on a thread two people trust.
  Future<void> _send(Future<void> Function() write) async {
    try {
      await write();
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'That did not send. Try again.');
    }
  }

  Future<void> _compose() async {
    final result = await ComposeSheet.show(context);
    if (result == null || !mounted) return;

    final me = feedWriteIdentity(ref);
    if (me == null) return;
    final service = ref.read(feedServiceProvider);

    await _send(() {
      if (result.secretDuration case final duration?) {
        return service.sendSecret(
          coupleId: me.coupleId,
          senderId: me.senderId,
          text: result.text,
          duration: duration,
        );
      }
      return service.sendText(
        coupleId: me.coupleId,
        senderId: me.senderId,
        text: result.text,
      );
    });
  }

  Future<void> _sendEmoji(String emoji, Offset origin) async {
    // The burst is local celebration, not state: it fires immediately whether
    // or not the write lands, because the thread's own copy arrives through
    // the listener a moment later.
    _burstKey.currentState?.fire(emoji, origin);

    final me = feedWriteIdentity(ref);
    if (me == null) return;

    await _send(
      () => ref
          .read(feedServiceProvider)
          .sendEmoji(
            coupleId: me.coupleId,
            senderId: me.senderId,
            emoji: emoji,
          ),
    );
  }

  /// Opens the reveal, which currently only reports that it cannot open.
  ///
  /// No body is fetched: `secretBodies` is readable only while the item is in
  /// `opening`, and nothing moves it there yet — **P3-01** owns the
  /// `sealed -> opening` transition. Rather than pretend, the reveal screen
  /// says so, and the secret stays sealed for whenever P3-01 lands.
  Future<void> _openSecret(SecretMessage secret) async {
    if (secret.isOpened) return;

    await context.push<SecretRevealResult>(
      AppRoutes.secretReveal,
      extra: SecretRevealArgs(
        secret: secret,
        senderName: ref.read(memberNameResolverProvider)(secret.senderId),
        body: null,
      ),
    );
  }

  Future<void> _setMood() async {
    final mood = await MoodSheet.show(
      context,
      partnerName: ref.read(partnerNameProvider),
    );
    if (mood == null || !mounted) return;

    await _send(
      () => ref
          .read(moodServiceProvider)
          .setMood(emoji: mood.emoji, note: mood.note),
    );
  }

  Future<void> _react(FeedItem item) async {
    final emoji = await ReactionTray.show(context);
    if (emoji == null || !mounted) return;

    final me = feedWriteIdentity(ref);
    if (me == null) return;

    await _send(
      () => ref
          .read(feedServiceProvider)
          .react(itemId: item.id, senderId: me.senderId, emoji: emoji),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read: the viewer and their favourites both come from it.
    final profile = ref.watch(currentUserProvider).valueOrNull;
    final feed = ref.watch(feedProvider);

    return Scaffold(
      backgroundColor: context.palette.feedBackground,
      body: Stack(
        children: [
          Column(
            children: [
              SafeArea(
                bottom: false,
                child: FeedHeader(
                  title: ref.watch(coupleTitleProvider),
                  // M-10: still mock. `anniversaryDate` is an open owner
                  // decision, so this cannot be computed honestly yet.
                  subtitle: '994 days · since 4 November 2023',
                  streak: 47,
                  viewerInitial: ref.watch(memberInitialResolverProvider)(
                    _viewerId,
                  ),
                  onOpenSettings: () => context.push(AppRoutes.settings),
                ),
              ),
              // Only the thread swaps between the three states. The header
              // above and the tray below never depend on `items`.
              Expanded(
                child: feed.when(
                  // Paging back is a reload of the same provider. Without
                  // this the thread would blink through the loading state
                  // every time the reader reached the top.
                  skipLoadingOnReload: true,
                  data: (page) => page.items.isEmpty
                      ? const FeedEmpty()
                      : _Thread(
                          items: page.items,
                          viewerId: _viewerId,
                          controller: _scrollController,
                          onReact: _react,
                          onOpenSecret: _openSecret,
                          onTapStatus: _setMood,
                        ),
                  loading: () => const FeedLoading(),
                  error: (_, _) => FeedError(onRetry: () => retryFeed(ref)),
                ),
              ),
              SafeArea(
                top: false,
                child: EmojiTray(
                  // The reader's own favourites, from their profile.
                  // `favoriteEmojis` is written with eight defaults by
                  // ensureUserProfile, so the fallback is only for the
                  // pre-resolve instant.
                  emoji: profile?.favoriteEmojis.isNotEmpty == true
                      ? profile!.favoriteEmojis
                      : defaultTrayEmoji,
                  onCompose: _compose,
                  onEmoji: _sendEmoji,
                ),
              ),
            ],
          ),
          // Sits above the thread so emoji fly over everything.
          Positioned.fill(child: EmojiBurstLayer(key: _burstKey)),
        ],
      ),
    );
  }
}

/// The messages themselves.
///
/// `reverse: true` rather than a scroll-to-bottom on load. It makes offset 0
/// the newest message, so the thread opens where it should with no post-frame
/// jump, and appending older pages at the far end does not shift what is on
/// screen. [items] arrives newest-first from the query, which is exactly the
/// order a reversed list wants.
class _Thread extends StatelessWidget {
  const _Thread({
    required this.items,
    required this.viewerId,
    required this.controller,
    required this.onReact,
    required this.onOpenSecret,
    required this.onTapStatus,
  });

  final List<FeedItem> items;
  final String viewerId;
  final ScrollController controller;
  final ValueChanged<FeedItem> onReact;
  final ValueChanged<SecretMessage> onOpenSecret;
  final VoidCallback onTapStatus;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      reverse: true,
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return FeedItemView(
          // Keyed by document id so a live update rebuilds the right row
          // rather than the row that happens to sit at that index.
          key: ValueKey(item.id),
          item: item,
          viewerId: viewerId,
          onLongPress: () => onReact(item),
          onOpenSecret: item is SecretMessage ? () => onOpenSecret(item) : null,
          onTapStatus: onTapStatus,
        );
      },
    );
  }
}

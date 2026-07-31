import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../common/app_router.dart';
import '../../../common/time_format.dart';
import '../../../theme/theme_colors.dart';
import '../../compose/compose_sheet.dart';
import '../../mood/mood_sheet.dart';
import '../../secret/screens/secret_reveal_screen.dart';
import '../../secret/widgets/secret_opened_dialog.dart';
import '../models/feed_item.dart';
import '../models/sample_thread.dart';
import '../widgets/emoji_burst.dart';
import '../widgets/emoji_tray.dart';
import '../widgets/feed_header.dart';
import '../widgets/feed_item_view.dart';
import '../widgets/reaction_tray.dart';

/// The shared thread. Rendered from [viewerId]'s side — tapping the header
/// avatar swaps perspective, which is how the sender and recipient layouts in
/// the mocks are both reachable without two accounts.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, this.viewerId = devonUid});

  /// uid of the signed-in reader. Comes from the auth provider at **P2-07**.
  final String viewerId;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _burstKey = GlobalKey<EmojiBurstLayerState>();
  final _scrollController = ScrollController();

  late String _viewerId = widget.viewerId;
  late List<FeedItem> _items = sampleThread();

  /// Stands in for the `secretBodies` collection until **P3-01**.
  final Map<String, String> _secretBodies = {...sampleSecretBodies};

  /// Client-side id for an item that has not been written yet. Firestore
  /// assigns the real one on write (**P2-12**).
  String _newItemId() => 'local-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    // Threads open at the newest message.
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _jumpToEnd() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  Future<void> _scrollToEnd() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _compose() async {
    final result = await ComposeSheet.show(context);
    if (result == null || !mounted) return;

    setState(() {
      final id = _newItemId();
      _items = [
        ..._items,
        if (result.secretDuration case final duration?)
          SecretMessage(
            id: id,
            senderId: _viewerId,
            createdAt: DateTime.now(),
            duration: duration,
          )
        else
          TextMessage(
            id: id,
            senderId: _viewerId,
            createdAt: DateTime.now(),
            text: result.text,
          ),
      ];
      // Bodies live apart from the tombstone; this stands in for the
      // `secretBodies` write until **P3-01**.
      if (result.isSecret) _secretBodies[id] = result.text;
    });
    await _scrollToEnd();
  }

  void _sendEmoji(String emoji, Offset origin) {
    _burstKey.currentState?.fire(emoji, origin);
    setState(() {
      _items = [
        ..._items,
        EmojiMessage(
          id: _newItemId(),
          senderId: _viewerId,
          createdAt: DateTime.now(),
          emoji: emoji,
        ),
      ];
    });
    _scrollToEnd();
  }

  /// Runs the full-screen reveal, then burns the secret for both people and
  /// tells the sender it was read.
  Future<void> _openSecret(int index) async {
    final secret = _items[index];
    if (secret is! SecretMessage || secret.isOpened) return;

    final result = await context.push<SecretRevealResult>(
      AppRoutes.secretReveal,
      extra: SecretRevealArgs(
        secret: secret,
        senderName: memberName(secret.senderId),
        body: _secretBodies[secret.id] ?? '',
      ),
    );
    if (result == null || !mounted) return;

    // Fixed while the thread is mock data. **P3-01** replaces this with the
    // server timestamp the deletion Function writes.
    final openedAt = DateTime(2026, 7, 30, 9, 31);
    setState(() {
      _items = [..._items];
      // Rebuilt rather than mutated: opening is a server operation, so the
      // client has no `markOpened()` to call.
      _items[index] = SecretMessage(
        id: secret.id,
        senderId: secret.senderId,
        createdAt: secret.createdAt,
        duration: secret.duration,
        secretState: SecretState.opened,
        openedAt: openedAt,
        heldFullCountdown: result.heldFullCountdown,
        reactions: secret.reactions,
      );
      _secretBodies.remove(secret.id);
    });

    // The sender's confirmation. Both sides are on this one device, so it is
    // shown here directly rather than pushed from a server.
    await SecretOpenedDialog.show(
      context,
      readerName: memberName(_viewerId),
      openedAt: formatClockTime(openedAt),
      heldFullCountdown: result.heldFullCountdown,
    );
  }

  Future<void> _setMood() async {
    final mood = await MoodSheet.show(
      context,
      partnerName: memberName(partnerOf(_viewerId)),
    );
    if (mood == null || !mounted) return;

    setState(() {
      _items = [
        for (final item in _items)
          if (item is StatusNote)
            StatusNote(
              id: item.id,
              senderId: item.senderId,
              createdAt: item.createdAt,
              text: mood.note.isEmpty ? 'set a mood' : mood.note,
              icon: mood.emoji,
              reactions: item.reactions,
            )
          else
            item,
      ];
    });
  }

  Future<void> _react(int index) async {
    final emoji = await ReactionTray.show(context);
    if (emoji == null || !mounted) return;

    setState(() {
      _items = [..._items];
      final target = _items[index];
      // Reactions are a map keyed by uid, so reacting twice replaces rather
      // than appends, and every item type carries them (brief §9).
      final reactions = {...target.reactions, _viewerId: emoji};
      _items[index] = switch (target) {
        TextMessage(:final text) => TextMessage(
          id: target.id,
          senderId: target.senderId,
          createdAt: target.createdAt,
          text: text,
          reactions: reactions,
        ),
        PhotoMessage(:final mediaUrl, :final caption) => PhotoMessage(
          id: target.id,
          senderId: target.senderId,
          createdAt: target.createdAt,
          mediaUrl: mediaUrl,
          caption: caption,
          reactions: reactions,
        ),
        final other => other,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.feedBackground,
      body: Stack(
        children: [
          Column(
            children: [
              SafeArea(
                bottom: false,
                child: FeedHeader(
                  title: 'Maya & Devon',
                  subtitle: '994 days · since 4 November 2023',
                  streak: 47,
                  viewerInitial: memberInitial(_viewerId),
                  onOpenSettings: () => context.push(AppRoutes.settings),
                  onSwapViewer: () =>
                      setState(() => _viewerId = partnerOf(_viewerId)),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  itemCount: _items.length,
                  itemBuilder: (context, index) => FeedItemView(
                    item: _items[index],
                    viewerId: _viewerId,
                    onLongPress: () => _react(index),
                    onOpenSecret: () => _openSecret(index),
                    onTapStatus: _setMood,
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: EmojiTray(
                  emoji: _viewerId == mayaUid ? mayaTrayEmoji : devonTrayEmoji,
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

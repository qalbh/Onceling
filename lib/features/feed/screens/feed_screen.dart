import 'package:flutter/material.dart';

import '../../../theme/theme_colors.dart';
import '../../compose/compose_sheet.dart';
import '../../mood/mood_sheet.dart';
import '../../secret/screens/secret_reveal_screen.dart';
import '../../secret/widgets/secret_opened_dialog.dart';
import '../../settings/screens/settings_screen.dart';
import '../models/feed_item.dart';
import '../models/sample_thread.dart';
import '../widgets/emoji_burst.dart';
import '../widgets/emoji_tray.dart';
import '../widgets/feed_header.dart';
import '../widgets/feed_item_view.dart';
import '../widgets/reaction_tray.dart';

/// The shared thread. Rendered from [viewer]'s side — tapping the header
/// avatar swaps perspective, which is how the sender and recipient layouts in
/// the mocks are both reachable without two accounts.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, this.viewer = Person.devon});

  static const routeName = '/feed';

  final Person viewer;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _burstKey = GlobalKey<EmojiBurstLayerState>();
  final _scrollController = ScrollController();

  late Person _viewer = widget.viewer;
  late List<FeedItem> _items = sampleThread();

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
      _items = [
        ..._items,
        if (result.secretDuration case final duration?)
          SecretMessage(
            sender: _viewer,
            time: 'now',
            duration: duration,
            body: result.text,
          )
        else
          TextMessage(
            sender: _viewer,
            text: result.text,
            time: 'now',
            delivered: true,
          ),
      ];
    });
    await _scrollToEnd();
  }

  void _sendEmoji(String emoji, Offset origin) {
    _burstKey.currentState?.fire(emoji, origin);
    setState(() {
      _items = [
        ..._items,
        EmojiMessage(sender: _viewer, emoji: emoji, time: 'now'),
      ];
    });
    _scrollToEnd();
  }

  /// Runs the full-screen reveal, then burns the secret for both people and
  /// tells the sender it was read.
  Future<void> _openSecret(int index) async {
    final secret = _items[index];
    if (secret is! SecretMessage || secret.isOpened) return;

    final result = await SecretRevealScreen.show(context, secret);
    if (result == null || !mounted) return;

    const openedAt = '9:31 AM';
    setState(() {
      _items = [..._items];
      _items[index] = secret.markOpened(
        openedAt,
        heldFull: result.heldFullCountdown,
      );
    });

    // The sender's confirmation. Both sides are on this one device, so it is
    // shown here directly rather than pushed from a server.
    await SecretOpenedDialog.show(
      context,
      reader: _viewer,
      openedAt: openedAt,
      heldFullCountdown: result.heldFullCountdown,
    );
  }

  Future<void> _setMood() async {
    final mood = await MoodSheet.show(context, partner: _viewer.other);
    if (mood == null || !mounted) return;

    setState(() {
      _items = [
        for (final item in _items)
          if (item is StatusNote)
            StatusNote(
              text: mood.note.isEmpty ? 'set a mood' : mood.note,
              icon: mood.emoji,
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
      _items[index] = switch (_items[index]) {
        TextMessage(
          :final sender,
          :final text,
          :final time,
          :final delivered,
        ) =>
          TextMessage(
            sender: sender,
            text: text,
            time: time,
            delivered: delivered,
            reaction: emoji,
          ),
        PhotoMessage(
          :final sender,
          :final placeholder,
          :final time,
          :final caption,
        ) =>
          PhotoMessage(
            sender: sender,
            placeholder: placeholder,
            time: time,
            caption: caption,
            reaction: emoji,
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
                  viewer: _viewer,
                  onOpenSettings: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsScreen(viewer: _viewer),
                    ),
                  ),
                  onSwapViewer: () => setState(() => _viewer = _viewer.other),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  itemCount: _items.length,
                  itemBuilder: (context, index) => FeedItemView(
                    item: _items[index],
                    viewer: _viewer,
                    onLongPress: () => _react(index),
                    onOpenSecret: () => _openSecret(index),
                    onTapStatus: _setMood,
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: EmojiTray(
                  emoji: _viewer == Person.maya
                      ? mayaTrayEmoji
                      : devonTrayEmoji,
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

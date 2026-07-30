import 'package:flutter/material.dart';

import '../../../theme/theme_colors.dart';
import '../models/feed_item.dart';
import 'feed_header.dart';
import 'secret_card.dart';

/// Renders one entry of the thread, mirrored depending on whether [viewer]
/// sent it. Outgoing sits right with the avatar in the right gutter; incoming
/// sits left with the avatar in the left gutter.
class FeedItemView extends StatelessWidget {
  const FeedItemView({
    super.key,
    required this.item,
    required this.viewer,
    this.onLongPress,
    this.onOpenSecret,
    this.onTapStatus,
  });

  final FeedItem item;
  final Person viewer;
  final VoidCallback? onLongPress;
  final VoidCallback? onOpenSecret;

  /// The status line doubles as the entry point to the mood picker.
  final VoidCallback? onTapStatus;

  @override
  Widget build(BuildContext context) {
    if (item case StatusNote(:final text, :final icon)) {
      return _StatusNoteView(text: text, icon: icon, onTap: onTapStatus);
    }

    final sender = switch (item) {
      TextMessage(:final sender) => sender,
      PhotoMessage(:final sender) => sender,
      EmojiMessage(:final sender) => sender,
      SecretMessage(:final sender) => sender,
      StatusNote() => viewer,
    };
    final isMine = sender == viewer;

    final avatar = PersonAvatar(person: sender, size: 34);
    final content = Flexible(
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [_body(context, isMine), ..._trailing(isMine)],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: isMine
            ? [content, const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), content],
      ),
    );
  }

  Widget _body(BuildContext context, bool isMine) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.74;

    return switch (item) {
      TextMessage(:final text) => GestureDetector(
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: _Bubble(text: text, isMine: isMine),
        ),
      ),
      PhotoMessage(:final placeholder, :final caption) => GestureDetector(
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            _PhotoWell(label: placeholder, width: maxWidth * 0.84),
            if (caption != null) ...[
              const SizedBox(height: 10),
              Text(caption, style: Theme.of(context).textTheme.headlineMedium),
            ],
          ],
        ),
      ),
      EmojiMessage(:final emoji, :final count) => GestureDetector(
        onLongPress: onLongPress,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: 6,
          children: [
            Text(emoji, style: Theme.of(context).textTheme.displayLarge),
            if (count > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '×$count',
                  style: Theme.of(context).textTheme.titleLarge!.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
      SecretMessage(:final duration, :final openedAt) => switch ((
        openedAt,
        isMine,
      )) {
        // Once read, both sides see the same spent marker.
        (final String at, _) => SecretOpenedBubble(openedAt: at),
        (null, true) => SecretSentBubble(duration: duration),
        (null, false) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth * 0.88),
          child: SecretCard(item: item as SecretMessage, onOpen: onOpenSecret),
        ),
      },
      StatusNote() => const SizedBox.shrink(),
    };
  }

  /// Timestamp line plus any reaction chip left on the message.
  List<Widget> _trailing(bool isMine) {
    final (time, reaction, delivered) = switch (item) {
      TextMessage(:final time, :final reaction, :final delivered) => (
        time,
        reaction,
        delivered,
      ),
      PhotoMessage(:final time, :final reaction) => (time, reaction, false),
      EmojiMessage(:final time) => (time, null, false),
      SecretMessage(:final time, :final delivered, :final openedAt) => (
        openedAt == null ? time : '$time · Opened',
        null,
        isMine && delivered && openedAt == null,
      ),
      StatusNote() => ('', null, false),
    };

    return [
      const SizedBox(height: 6),
      Builder(
        builder: (context) => Text(
          delivered ? '$time · Delivered' : time,
          textAlign: isMine ? TextAlign.right : TextAlign.left,
          style: Theme.of(
            context,
          ).textTheme.titleSmall!.copyWith(color: context.palette.inkFaint),
        ),
      ),
      if (reaction != null) ...[
        const SizedBox(height: 6),
        _ReactionChip(emoji: reaction),
      ],
    ];
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.isMine});

  final String text;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: isMine ? palette.bubbleMine : palette.bubbleTheirs,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        text,
        style: theme.textTheme.headlineLarge!.copyWith(
          height: 1.35,
          color: isMine
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Stand-in for an attached photo until real image handling exists.
class _PhotoWell extends StatelessWidget {
  const _PhotoWell({required this.label, required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: width,
      height: width / 1.26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.palette.photoPlaceholder,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest.withValues(
            alpha: 0.72,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: theme.textTheme.titleSmall!.copyWith(
            fontFamily: 'Menlo',
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: ShapeDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        shape: const StadiumBorder(),
      ),
      // A reaction is content someone sent, so it scales with text.
      child: Text(emoji, style: theme.textTheme.bodyLarge),
    );
  }
}

class _StatusNoteView extends StatelessWidget {
  const _StatusNoteView({required this.text, this.icon, this.onTap});

  final String text;
  final String? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8,
          children: [
            // The mood emoji is the partner's content and sits inline with
            // body copy, so it scales alongside it.
            if (icon != null)
              Text(icon!, style: Theme.of(context).textTheme.titleLarge),
            Text(
              text,
              style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                color: context.palette.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

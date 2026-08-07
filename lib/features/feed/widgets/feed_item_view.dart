import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/time_format.dart';
import '../../../theme/theme_colors.dart';
import '../../../theme/theme_glyphs.dart';
import '../../pairing/couple_names.dart';
import '../../milestone/milestone_copy.dart';
import '../models/feed_item.dart';
import 'feed_header.dart';
import 'secret_card.dart';

/// Renders one entry of the thread, mirrored depending on whether [viewerId]
/// sent it. Outgoing sits right with the avatar in the right gutter; incoming
/// sits left with the avatar in the left gutter.
class FeedItemView extends ConsumerWidget {
  const FeedItemView({
    super.key,
    required this.item,
    required this.viewerId,
    this.onLongPress,
    this.onOpenSecret,
    this.onTapStatus,
  });

  final FeedItem item;

  /// uid of the signed-in reader. Sent-vs-received is this compared against
  /// `item.senderId`.
  final String viewerId;
  final VoidCallback? onLongPress;
  final VoidCallback? onOpenSecret;

  /// The status line doubles as the entry point to the mood picker.
  final VoidCallback? onTapStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item case StatusNote(:final text, :final icon)) {
      return _StatusNoteView(text: text, icon: icon, onTap: onTapStatus);
    }

    // Centred like a status note, for the same reason stated the same way:
    // it belongs to neither side of the thread. A milestone is the one item
    // with no author at all, so mirroring it toward either partner would be
    // claiming it for them.
    if (item case MilestoneMessage(:final day)) {
      return _MilestoneView(day: day);
    }

    final isMine = item.senderId == viewerId;

    final avatar = PersonAvatar(
      initial: ref.watch(memberInitialResolverProvider)(item.senderId),
      size: 34,
    );
    final content = Flexible(
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [_body(context, ref, isMine), ..._trailing(isMine)],
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

  Widget _body(BuildContext context, WidgetRef ref, bool isMine) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.74;

    return switch (item) {
      TextMessage(:final text) => GestureDetector(
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: _Bubble(text: text, isMine: isMine),
        ),
      ),
      PhotoMessage(:final mediaUrl, :final caption) => GestureDetector(
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            _PhotoWell(mediaUrl: mediaUrl, width: maxWidth * 0.84),
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
        (final DateTime at, _) => SecretOpenedBubble(
          openedAt: formatClockTime(at),
        ),
        (null, true) => SecretSentBubble(duration: duration),
        (null, false) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth * 0.88),
          child: SecretCard(
            item: item as SecretMessage,
            senderName: ref.watch(memberNameResolverProvider)(item.senderId),
            onOpen: onOpenSecret,
          ),
        ),
      },
      StatusNote() => const SizedBox.shrink(),
      MilestoneMessage() => const SizedBox.shrink(),
    };
  }

  /// Timestamp line plus any reactions left on the message.
  List<Widget> _trailing(bool isMine) {
    final clock = formatClockTime(item.createdAt);
    final time = switch (item) {
      SecretMessage(:final openedAt) when openedAt != null => '$clock · Opened',
      _ => clock,
    };

    return [
      const SizedBox(height: 6),
      Builder(
        builder: (context) => Text(
          time,
          textAlign: isMine ? TextAlign.right : TextAlign.left,
          style: Theme.of(
            context,
          ).textTheme.titleSmall!.copyWith(color: context.palette.inkFaint),
        ),
      ),
      if (item.reactions.isNotEmpty) ...[
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            for (final emoji in item.reactions.values)
              _ReactionChip(emoji: emoji),
          ],
        ),
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

/// Stand-in for an attached photo until real image handling exists (**P2-13**).
class _PhotoWell extends StatelessWidget {
  const _PhotoWell({required this.mediaUrl, required this.width});

  final String? mediaUrl;
  final double width;

  @override
  Widget build(BuildContext context) {
    final url = mediaUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: width,
        height: width / 1.26,
        // **P2-15: all three states, none of them a bare grey box.**
        //
        // Empty is a real case rather than a defensive one: an item whose
        // upload is still finishing has no `mediaUrl` yet, and P2-13 writes the
        // document only after the object lands — so this is what a photo from
        // an older client, or a genuinely broken write, looks like.
        child: url == null || url.isEmpty
            ? const _PhotoState(glyph: '🖼️', label: 'Photo unavailable')
            : Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  final expected = progress.expectedTotalBytes;
                  return _PhotoState(
                    glyph: '🖼️',
                    label: 'Loading',
                    progress: expected == null
                        ? null
                        : progress.cumulativeBytesLoaded / expected,
                  );
                },
                // A URL that 404s or times out. Saying so is the whole point:
                // a silent grey rectangle reads as our bug, and leaves the
                // person with nothing to do about it.
                errorBuilder: (context, error, stack) => const _PhotoState(
                  glyph: '🌥️',
                  label: "This photo didn't load",
                ),
              ),
      ),
    );
  }
}

/// Loading, empty and error inside the photo's own footprint.
///
/// One widget for all three so they cannot drift in size — the bubble must not
/// resize when an image resolves, or the feed jumps under a reader's thumb.
class _PhotoState extends StatelessWidget {
  const _PhotoState({required this.glyph, required this.label, this.progress});

  final String glyph;
  final String label;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: context.palette.photoPlaceholder,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(glyph, size: context.glyphs.emptyState),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: 96,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: theme.colorScheme.surfaceContainerLowest,
              ),
            ),
          ],
        ],
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

/// A milestone crossing, centred in the scrollback (**P3-03**).
///
/// Quieter than the full-screen moment on purpose: the moment is the
/// celebration, this is the record of it. The feed shows the day and one line
/// so scrolling back through a year of thread passes the milestones the way a
/// photo album passes birthdays.
class _MilestoneView extends StatelessWidget {
  const _MilestoneView({required this.day});

  final int day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 32),
      child: Column(
        children: [
          Glyph('\u{1F338}', size: context.glyphs.sealBadge),
          const SizedBox(height: 6),
          Text(
            'Day $day',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            milestoneLine(day),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium!.copyWith(
              color: context.palette.inkFaint,
            ),
          ),
        ],
      ),
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

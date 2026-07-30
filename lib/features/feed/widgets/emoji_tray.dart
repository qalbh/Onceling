import 'package:flutter/material.dart';

import '../../../theme/theme_glyphs.dart';

/// Floating quick-reaction bar. The plus opens compose; each emoji fires a
/// burst and sends it to the thread.
class EmojiTray extends StatelessWidget {
  const EmojiTray({
    super.key,
    required this.emoji,
    required this.onCompose,
    required this.onEmoji,
  });

  final List<String> emoji;
  final VoidCallback onCompose;

  /// Reports the tapped emoji and the global position it was tapped at, so the
  /// burst can start from the emoji itself.
  final void Function(String emoji, Offset origin) onEmoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: ShapeDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        shape: const StadiumBorder(),
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _ComposeButton(onTap: onCompose),
          // Scales the row down rather than overflowing on narrow screens.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                children: [
                  for (final e in emoji) _TrayEmoji(emoji: e, onTap: onEmoji),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposeButton extends StatelessWidget {
  const _ComposeButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.add,
          size: 24,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _TrayEmoji extends StatefulWidget {
  const _TrayEmoji({required this.emoji, required this.onTap});

  final String emoji;
  final void Function(String emoji, Offset origin) onTap;

  @override
  State<_TrayEmoji> createState() => _TrayEmojiState();
}

class _TrayEmojiState extends State<_TrayEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    lowerBound: 0,
    upperBound: 1,
  );

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _handleTap() {
    _pop.forward(from: 0).then((_) => _pop.reverse());

    // Fire from the centre of this emoji so the burst reads as coming from it.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? Offset.zero
        : box.localToGlobal(box.size.center(Offset.zero));
    widget.onTap(widget.emoji, origin);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 1.0,
            end: 1.45,
          ).animate(CurvedAnimation(parent: _pop, curve: Curves.easeOutBack)),
          child: Glyph(widget.emoji, size: context.glyphs.traySlot),
        ),
      ),
    );
  }
}

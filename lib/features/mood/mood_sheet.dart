import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_colors.dart';
import '../../theme/theme_glyphs.dart';

/// A mood is one emoji plus a short line, shown to the other person as an
/// ambient note in the thread rather than a notification.
class Mood {
  const Mood({required this.emoji, required this.note});

  final String emoji;
  final String note;
}

const moodEmoji = [
  '🥰',
  '😌',
  '🥲',
  '😴',
  '🔥',
  '🫠',
  '😏',
  '☕',
  '🌧️',
  '🎧',
  '🐢',
  '🫶',
];

/// Bottom sheet for setting your own mood.
class MoodSheet extends StatefulWidget {
  const MoodSheet({super.key, required this.partnerName, this.initial});

  final String partnerName;
  final Mood? initial;

  static Future<Mood?> show(
    BuildContext context, {
    required String partnerName,
    Mood? initial,
  }) {
    return showModalBottomSheet<Mood>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (_) => MoodSheet(partnerName: partnerName, initial: initial),
    );
  }

  @override
  State<MoodSheet> createState() => _MoodSheetState();
}

class _MoodSheetState extends State<MoodSheet> {
  static const _maxNote = 30;

  late String _emoji = widget.initial?.emoji ?? moodEmoji.first;
  late final _note = TextEditingController(text: widget.initial?.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outline,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'How are you, really?',
                  style: AppTheme.wordmark(context, 28),
                ),
                const SizedBox(height: 20),
                _emojiGrid(),
                const SizedBox(height: 18),
                _noteField(),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${_note.text.characters.length}/$_maxNote',
                    style: theme.textTheme.titleSmall!.copyWith(
                      color: context.palette.inkFaint,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _setButton(),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    '${widget.partnerName} gets a quiet nudge — no badge, '
                    'no sound.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: context.palette.inkFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emojiGrid() {
    return GridView.count(
      crossAxisCount: 6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        for (final emoji in moodEmoji)
          _MoodTile(
            emoji: emoji,
            selected: emoji == _emoji,
            onTap: () => setState(() => _emoji = emoji),
          ),
      ],
    );
  }

  Widget _noteField() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: TextField(
        controller: _note,
        maxLength: _maxNote,
        style: theme.textTheme.headlineLarge,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          counterText: '',
          hintText: 'in a word or two',
          hintStyle: theme.textTheme.headlineLarge!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _setButton() {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton(
        onPressed: () => Navigator.of(
          context,
        ).pop(Mood(emoji: _emoji, note: _note.text.trim())),
        style: FilledButton.styleFrom(
          backgroundColor: context.palette.bubbleMine,
          foregroundColor: theme.colorScheme.onPrimary,
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: AppTheme.bold(theme.textTheme.headlineLarge!),
        ),
        child: const Text('Set my mood'),
      ),
    );
  }
}

class _MoodTile extends StatelessWidget {
  const _MoodTile({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.6)
              : theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? theme.colorScheme.tertiary
                : theme.colorScheme.outline,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Glyph(emoji, size: context.glyphs.moodTile),
      ),
    );
  }
}

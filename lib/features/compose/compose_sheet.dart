import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tandem_colors.dart';
import '../../theme/tandem_glyphs.dart';
import '../feed/models/feed_item.dart';

/// What compose hands back when the user sends.
class ComposeResult {
  const ComposeResult({required this.text, this.secretDuration});

  final String text;

  /// Null for an ordinary message; set when sealed as a secret.
  final SecretDuration? secretDuration;

  bool get isSecret => secretDuration != null;
}

/// Bottom sheet for writing a message. Toggling "Secret" morphs it in place:
/// the title, placeholder and send label change and the timer panel expands.
class ComposeSheet extends StatefulWidget {
  const ComposeSheet({super.key});

  static Future<ComposeResult?> show(BuildContext context) {
    return showModalBottomSheet<ComposeResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (_) => const ComposeSheet(),
    );
  }

  @override
  State<ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<ComposeSheet> {
  final _controller = TextEditingController();
  bool _isSecret = false;
  SecretDuration _duration = SecretDuration.thirtySeconds;

  bool get _canSend => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    Navigator.of(context).pop(
      ComposeResult(
        text: _controller.text.trim(),
        secretDuration: _isSecret ? _duration : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      // Lift the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        // Secret mode adds the timer panel, so the sheet can outgrow a short
        // screen — cap it and let the contents scroll.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _DragHandle(),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      _isSecret ? 'A secret' : 'Say something',
                      key: ValueKey(_isSecret),
                      style: AppTheme.wordmark(context, 30),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _field(),
                  const SizedBox(height: 18),
                  _chips(),
                  // Timer panel only exists in secret mode.
                  if (_isSecret) ...[
                    const SizedBox(height: 18),
                    _TimerPanel(
                      selected: _duration,
                      onSelect: (d) => setState(() => _duration = d),
                    ),
                  ],
                  const SizedBox(height: 22),
                  _sendButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field() {
    final theme = Theme.of(context);

    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: TextField(
        controller: _controller,
        autofocus: false,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: theme.textTheme.headlineLarge!.copyWith(height: 1.35),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: _isSecret ? 'Only they will see this. Once.' : 'What is it?',
          hintStyle: theme.textTheme.headlineLarge!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _chips() {
    // Wrap rather than Row so long labels or large text settings push the
    // second chip onto its own line instead of overflowing.
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _ComposeChip(
          label: 'Add photo',
          selected: false,
          onTap: () {},
        ),
        _ComposeChip(
          label: 'Secret',
          leading: '🔒',
          selected: _isSecret,
          onTap: () => setState(() => _isSecret = !_isSecret),
        ),
      ],
    );
  }

  Widget _sendButton() {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton(
        onPressed: _canSend ? _send : null,
        style: FilledButton.styleFrom(
          backgroundColor: context.tandem.bubbleMine,
          foregroundColor: theme.colorScheme.onPrimary,
          disabledBackgroundColor: context.tandem.sageDisabled,
          disabledForegroundColor: theme.colorScheme.onPrimary,
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: AppTheme.bold(theme.textTheme.headlineLarge!),
        ),
        child: Text(_isSecret ? 'Seal & send' : 'Send'),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 46,
        height: 5,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outline,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _ComposeChip extends StatelessWidget {
  const _ComposeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
  });

  final String label;
  final String? leading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.tandem;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: ShapeDecoration(
          color: selected
              ? palette.bubbleMine
              : theme.colorScheme.surfaceContainerLowest,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? palette.bubbleMine : theme.colorScheme.outline,
              width: 1.2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            if (leading != null)
              Glyph(leading!, size: context.glyphs.chipLock),
            Text(
              label,
              style: theme.textTheme.bodyLarge!.copyWith(
                fontWeight: FontWeight.w600,
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "They can read it for" — how long the recipient gets once they open it.
class _TimerPanel extends StatelessWidget {
  const _TimerPanel({required this.selected, required this.onSelect});

  final SecretDuration selected;
  final ValueChanged<SecretDuration> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'They can read it for',
            style: theme.textTheme.bodyLarge!.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final duration in SecretDuration.values)
                _DurationChip(
                  label: duration.label,
                  selected: duration == selected,
                  onTap: () => onSelect(duration),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Then it is gone from our servers too. You will see the moment it '
            'is opened.',
            style: theme.textTheme.titleMedium!.copyWith(
              height: 1.4,
              color: context.tandem.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: ShapeDecoration(
          color: selected
              ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.5)
              : theme.colorScheme.surfaceContainerLowest,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.outline,
              width: 1.2,
            ),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.headlineSmall!.copyWith(
            fontWeight: FontWeight.w600,
            color: selected
                ? theme.colorScheme.onSecondaryContainer
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

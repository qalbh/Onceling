import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/tandem_colors.dart';
import '../../feed/models/feed_item.dart';

/// Typed confirmation before erasing the pair. Deliberately awkward: the word
/// must be typed exactly before the destructive button becomes live.
class UnpairSheet extends StatefulWidget {
  const UnpairSheet({super.key, required this.partner, required this.streak});

  final Person partner;
  final int streak;

  /// Resolves true only if the user confirmed.
  static Future<bool?> show(
    BuildContext context, {
    required Person partner,
    required int streak,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (_) => UnpairSheet(partner: partner, streak: streak),
    );
  }

  @override
  State<UnpairSheet> createState() => _UnpairSheetState();
}

class _UnpairSheetState extends State<UnpairSheet> {
  static const _phrase = 'UNPAIR';

  final _controller = TextEditingController();

  bool get _confirmed => _controller.text.trim() == _phrase;

  @override
  void dispose() {
    _controller.dispose();
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
                const SizedBox(height: 22),
                Text('Are you sure?', style: AppTheme.wordmark(context, 28)),
                const SizedBox(height: 16),
                Text(
                  'Unpairing erases everything you two made here — every note, '
                  'photo, secret, and your ${widget.streak}-day streak. It '
                  'happens for ${widget.partner.name} at the same moment, and '
                  'there is no undo.',
                  style: theme.textTheme.headlineMedium!.copyWith(
                    height: 1.45,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Type $_phrase to confirm',
                  style: theme.textTheme.titleMedium!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                _field(),
                const SizedBox(height: 22),
                _buttons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: _controller,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.characters,
        onChanged: (_) => setState(() {}),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
          TextInputFormatter.withFunction(
            (_, next) => next.copyWith(text: next.text.toUpperCase()),
          ),
        ],
        style: theme.textTheme.displaySmall!.copyWith(
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: _phrase,
          hintStyle: theme.textTheme.displaySmall!.copyWith(
            color: context.tandem.inkFaint,
          ),
        ),
      ),
    );
  }

  Widget _buttons() {
    final theme = Theme.of(context);

    return Row(
      spacing: 12,
      children: [
        Expanded(
          child: SizedBox(
            height: 56,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurface,
                side: BorderSide(color: theme.colorScheme.outline, width: 1.2),
                shape: const StadiumBorder(),
                textStyle: AppTheme.bold(theme.textTheme.headlineMedium!),
              ),
              child: const Text('Keep us'),
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _confirmed
                  ? () => Navigator.of(context).pop(true)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                disabledBackgroundColor: theme.colorScheme.error.withValues(
                  alpha: 0.45,
                ),
                disabledForegroundColor: theme.colorScheme.onError,
                elevation: 0,
                shape: const StadiumBorder(),
                textStyle: AppTheme.bold(theme.textTheme.headlineMedium!),
              ),
              child: const Text('Unpair'),
            ),
          ),
        ),
      ],
    );
  }
}

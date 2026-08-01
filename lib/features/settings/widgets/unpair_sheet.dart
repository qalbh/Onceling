import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/providers.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';

/// Typed confirmation before erasing the pair. Deliberately awkward: the word
/// must be typed exactly before the destructive button becomes live.
class UnpairSheet extends ConsumerStatefulWidget {
  const UnpairSheet({
    super.key,
    required this.partnerName,
    required this.streak,
  });

  final String partnerName;
  final int streak;

  /// Resolves true only if the user confirmed.
  static Future<bool?> show(
    BuildContext context, {
    required String partnerName,
    required int streak,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (_) => UnpairSheet(partnerName: partnerName, streak: streak),
    );
  }

  @override
  ConsumerState<UnpairSheet> createState() => _UnpairSheetState();
}

class _UnpairSheetState extends ConsumerState<UnpairSheet> {
  static const _phrase = 'UNPAIR';

  bool _busy = false;
  String? _error;

  /// Calls **P2-36** phase 1 and reports the outcome here.
  ///
  /// Popping on success is safe, unlike the auth sheet: clearing `coupleId`
  /// makes the gate want `/pairing`, and `/settings` is inside the pairing
  /// area's allowed set, so the redirect returns STAY and no page-stack
  /// replacement happens under this sheet. There is nothing to race.
  ///
  /// On failure nothing navigated, so the sheet stays open holding the error —
  /// it is still the user's context for deciding what to do.
  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(pairingServiceProvider).unpair();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      developer.log('unpair failed: $error', name: 'UnpairSheet');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'That did not go through. Check your connection and try again.';
      });
    }
  }

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
                  'happens for ${widget.partnerName} at the same moment, and '
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
                _error0(),
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
            color: context.palette.inkFaint,
          ),
        ),
      ),
    );
  }

  Widget _error0() {
    final theme = Theme.of(context);
    if (_error case final message?) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          message,
          key: const Key('unpair-error'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium!.copyWith(
            color: context.palette.dangerInk,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
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
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
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
              onPressed: (_confirmed && !_busy) ? _confirm : null,
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
              child: Text(_busy ? 'Unpairing…' : 'Unpair'),
            ),
          ),
        ),
      ],
    );
  }
}

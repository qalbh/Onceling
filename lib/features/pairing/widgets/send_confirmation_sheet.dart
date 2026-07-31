import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/providers.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../pairing_errors.dart';

/// **P2-23** — confirm before sending, with the code echoed back.
///
/// Returns true when a request was actually created.
Future<bool?> showSendConfirmationSheet(BuildContext context, String code) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SendConfirmationSheet(code: code),
  );
}

/// The sheet body.
///
/// **Shows nothing about who owns the code.** No name, no avatar, no "pair with
/// Maya?" — B must learn nothing about A until A accepts (**P2-23**). The
/// callable enforces this by returning only a request id; this sheet is the
/// other half of that promise, and it will feel under-informative on purpose.
class SendConfirmationSheet extends ConsumerStatefulWidget {
  const SendConfirmationSheet({super.key, required this.code});

  final String code;

  @override
  ConsumerState<SendConfirmationSheet> createState() =>
      _SendConfirmationSheetState();
}

class _SendConfirmationSheetState extends ConsumerState<SendConfirmationSheet> {
  bool _sending = false;
  String? _error;

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(pairingServiceProvider).requestPairing(widget.code);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = pairingErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        // No TextField here, but the sheet can still be open over a keyboard
        // that has not finished dismissing.
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.palette.disabled,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Send a pairing request?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineLarge,
                ),
                const SizedBox(height: 16),
                _CodeEcho(code: widget.code),
                const SizedBox(height: 16),
                Text(
                  "They will see it next time they open Onceling. Nothing is "
                  "shared until they accept.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_error case final message?) ...[
                  const SizedBox(height: 16),
                  Text(
                    message,
                    key: const Key('send-error'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium!.copyWith(
                      color: context.palette.dangerInk,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _sending ? null : _send,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      disabledBackgroundColor: context.palette.disabled,
                      disabledForegroundColor: theme.colorScheme.onPrimary,
                      elevation: 0,
                      shape: const StadiumBorder(),
                      textStyle: AppTheme.bold(theme.textTheme.bodyLarge!),
                    ),
                    child: Text(_sending ? 'Sending…' : 'Send'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: TextButton(
                    onPressed: _sending
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                      textStyle: AppTheme.bold(theme.textTheme.bodyLarge!),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The code, spaced out so a transposed character is catchable at a glance.
class _CodeEcho extends StatelessWidget {
  const _CodeEcho({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: context.palette.tile,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        code.split('').join(' '),
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineLarge,
      ),
    );
  }
}

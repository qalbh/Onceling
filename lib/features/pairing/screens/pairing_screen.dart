import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/app_router.dart';
import '../../../common/app_toast.dart';
import '../../../common/providers.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../widgets/code_tiles.dart';
import '../widgets/partner_code_field.dart';

/// Pairing step: share your own code, or enter your partner's.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key, this.myCode = 'MK4Q7B', this.onPair});

  /// Fallback while the profile has no code yet — mock-era placeholder.
  final String myCode;

  /// Called with the partner's code once six characters are entered.
  final ValueChanged<String>? onPair;

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  static const _codeLength = 6;
  final _partnerCode = TextEditingController();

  /// One claim attempt per screen visit; the callable is idempotent anyway.
  bool _codeRequested = false;

  /// Resolved in build(): the profile's real code, or the mock fallback.
  String _shownCode = '';

  bool get _canPair => _partnerCode.text.length == _codeLength;

  @override
  void dispose() {
    _partnerCode.dispose();
    super.dispose();
  }

  /// P2-08 client edge: if the signed-in profile has no code, claim one. The
  /// document stream repaints the tiles when the server write lands.
  void _ensureCodeIfMissing() {
    final profile = ref.read(currentUserProvider).valueOrNull;
    if (_codeRequested ||
        profile == null ||
        profile.isPaired ||
        profile.pairingCode != null) {
      return;
    }
    _codeRequested = true;
    ref.read(pairingServiceProvider).ensurePairingCode().catchError((
      Object error,
    ) {
      developer.log('ensurePairingCode failed: $error', name: 'PairingScreen');
      if (mounted) setState(() => _codeRequested = false); // allow retry
      return '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ref.listen(currentUserProvider, (_, _) => _ensureCodeIfMissing());
    _ensureCodeIfMissing();
    _shownCode =
        ref.watch(currentUserProvider).valueOrNull?.pairingCode ??
        widget.myCode;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Find your person', style: AppTheme.wordmark(context, 30)),
              const SizedBox(height: 14),
              Text(
                'One code, one partner, forever after.',
                style: theme.textTheme.headlineMedium!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _Card(child: _shareSection()),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  'or',
                  style: theme.textTheme.titleLarge!.copyWith(
                    color: context.palette.inkFaint,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _Card(child: _enterSection()),
              const SizedBox(height: 26),
              Center(
                child: Text(
                  'You can only ever be paired with one person.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium!.copyWith(
                    color: context.palette.inkFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shareSection() {
    return Column(
      children: [
        const _SectionLabel('YOUR CODE'),
        const SizedBox(height: 20),
        CodeTiles(code: _shownCode),
        const SizedBox(height: 22),
        Row(
          spacing: 14,
          children: [
            Expanded(
              child: _PairingButton(
                label: 'Copy code',
                filled: false,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _shownCode));
                  if (!mounted) return;
                  showAppToast(context, 'Code copied');
                },
              ),
            ),
            Expanded(
              child: _PairingButton(
                label: 'Share link',
                filled: true,
                onPressed: () => showAppToast(context, 'Share link tapped'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _enterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('ENTER THEIRS'),
        const SizedBox(height: 20),
        PartnerCodeField(
          controller: _partnerCode,
          length: _codeLength,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        _PairingButton(
          label: 'Pair us',
          filled: true,
          onPressed: _canPair
              ? () {
                  final code = _partnerCode.text;
                  if (widget.onPair case final onPair?) {
                    onPair(code);
                    return;
                  }
                  // Pairing is one-way: the thread replaces this screen. The
                  // redirect owns the real decision; this is the mock path
                  // until P2-09b sets coupleId server-side.
                  context.go(AppRoutes.feed);
                }
              : null,
        ),
      ],
    );
  }
}

/// White rounded panel the two sections sit in.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.labelSmall!.copyWith(color: context.palette.inkFaint),
    );
  }
}

/// Pill button sized for the pairing cards — shorter than the sign-in ones.
class _PairingButton extends StatelessWidget {
  const _PairingButton({
    required this.label,
    required this.filled,
    this.onPressed,
  });

  final String label;
  final bool filled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = AppTheme.bold(theme.textTheme.bodyLarge!);

    return SizedBox(
      height: 52,
      child: filled
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                disabledBackgroundColor: context.palette.disabled,
                disabledForegroundColor: theme.colorScheme.onPrimary,
                elevation: 0,
                shape: const StadiumBorder(),
                textStyle: textStyle,
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurface,
                side: BorderSide(color: theme.colorScheme.outline, width: 1.2),
                shape: const StadiumBorder(),
                textStyle: textStyle,
              ),
              child: Text(label),
            ),
    );
  }
}

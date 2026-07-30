import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../common/app_toast.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../../feed/screens/feed_screen.dart';
import '../widgets/code_tiles.dart';
import '../widgets/partner_code_field.dart';

/// Pairing step: share your own code, or enter your partner's.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, this.myCode = 'MK4Q7B', this.onPair});

  static const routeName = '/pairing';

  final String myCode;

  /// Called with the partner's code once six characters are entered.
  final ValueChanged<String>? onPair;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  static const _codeLength = 6;
  final _partnerCode = TextEditingController();

  bool get _canPair => _partnerCode.text.length == _codeLength;

  @override
  void dispose() {
    _partnerCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
        CodeTiles(code: widget.myCode),
        const SizedBox(height: 22),
        Row(
          spacing: 14,
          children: [
            Expanded(
              child: _PairingButton(
                label: 'Copy code',
                filled: false,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.myCode));
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
                  // Pairing is one-way: the thread replaces this screen.
                  Navigator.of(
                    context,
                  ).pushReplacementNamed(FeedScreen.routeName);
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

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Floor, not a fixed height.
///
/// This was `SizedBox(height: 58)`, which cannot survive 200% text scale: the
/// label grows and the box does not, so it clips. A minimum plus real padding
/// gives the same 58 at normal scale and lets the button grow when it must.
const _kButtonMinHeight = 58.0;

/// One sign-in option. **Both options use this — there is no primary.**
///
/// The screen used to pair a filled dark pill (Apple) with an outlined one
/// (Google), which made Apple the visual default. Apple is gone until there is
/// a paid Apple Developer account (**P2-20**), and the two that remain are
/// genuinely equal choices: neither Google nor email is the one we would rather
/// you picked. Styling one as primary would be a recommendation we do not mean.
///
/// So: same shape, same height, same weight, same treatment. The only
/// difference between instances is the label and an optional leading mark.
class AuthButton extends StatelessWidget {
  const AuthButton({super.key, required this.label, this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;

  /// Optional leading mark, sized by the caller.
  ///
  /// Exists for the official Google "G". It is **not** wired yet: there is no
  /// brand asset in `assets/images/`, and an approximated Google logo is worse
  /// than none — it is the one mark that must be pixel-correct or absent.
  /// Drop the official asset in and pass it here; nothing else changes.
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.colorScheme.onSurface,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: theme.colorScheme.outline, width: 1.2),
        shape: const StadiumBorder(),
        minimumSize: const Size(double.infinity, _kButtonMinHeight),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        textStyle: AppTheme.bold(
          theme.textTheme.headlineLarge!,
        ).copyWith(letterSpacing: 0.1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final mark?) ...[mark, const SizedBox(width: 12)],
          // Flexible, not Expanded: at normal scale the label sets its own
          // width and stays centred; at 200% it wraps instead of overflowing.
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

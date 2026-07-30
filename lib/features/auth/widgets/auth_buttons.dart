import 'package:flutter/material.dart';


import '../../../theme/app_theme.dart';
const _kButtonHeight = 58.0;
const _kRadius = 40.0;

/// Filled dark pill — "Continue with Apple".
class PrimaryAuthButton extends StatelessWidget {
  const PrimaryAuthButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: _kButtonHeight,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: AppTheme.bold(
            theme.textTheme.headlineLarge!,
          ).copyWith(letterSpacing: 0.1),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Outlined pill on the paper background — "Continue with Google".
class SecondaryAuthButton extends StatelessWidget {
  const SecondaryAuthButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: _kButtonHeight,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
          backgroundColor: Colors.transparent,
          side: BorderSide(color: theme.colorScheme.outline, width: 1.2),
          shape: const StadiumBorder(),
          textStyle: AppTheme.bold(
            theme.textTheme.headlineLarge!,
          ).copyWith(letterSpacing: 0.1),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Plain underlined text action — "Use email or phone".
class UnderlinedTextButton extends StatelessWidget {
  const UnderlinedTextButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kRadius),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.headlineMedium!.copyWith(
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationThickness: 1.4,
        ),
      ),
    );
  }
}

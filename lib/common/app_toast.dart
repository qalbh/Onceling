import 'package:flutter/material.dart';

/// Dark stadium toast used for lightweight confirmations across the app.
void showAppToast(BuildContext context, String message) {
  final theme = Theme.of(context);

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: theme.textTheme.titleLarge!.copyWith(
            color: theme.colorScheme.surface,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: theme.colorScheme.onSurface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
        margin: const EdgeInsets.fromLTRB(28, 0, 28, 24),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    );
}

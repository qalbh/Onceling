import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../../../theme/theme_glyphs.dart';
import '../widgets/auth_buttons.dart';
import '../widgets/email_auth_sheet.dart';
import '../widgets/floral_hero.dart';

/// Entry screen: brand mark over the bouquet, sign-in options pinned low.
///
/// Email is the working path. Apple (**P2-20**) and Google (**P2-19**) are not
/// wired to a provider yet, so their buttons sit disabled rather than doing
/// something misleading — the UI stays, the behaviour waits.
///
/// Nothing here navigates on success: auth-gated routing is **P2-14**.
class SignInScreen extends StatelessWidget {
  const SignInScreen({
    super.key,
    this.onContinueWithApple,
    this.onContinueWithGoogle,
    this.onUseEmailOrPhone,
  });

  /// Null until **P2-20** wires Apple; the button renders disabled.
  final VoidCallback? onContinueWithApple;

  /// Null until **P2-19** wires Google; the button renders disabled.
  final VoidCallback? onContinueWithGoogle;

  /// Defaults to opening [EmailAuthSheet].
  final VoidCallback? onUseEmailOrPhone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        const SizedBox(height: 14),
                        const _PrivateSpaceBadge(),
                        const SizedBox(height: 22),
                        const FloralHero(),
                        const SizedBox(height: 28),
                        Text('Onceling', style: AppTheme.wordmark(context, 54)),
                        const SizedBox(height: 16),
                        Text(
                          'Where two become one story.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineLarge!.copyWith(
                            height: 1.3,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(height: 24),
                        PrimaryAuthButton(
                          label: 'Continue with Apple',
                          onPressed: onContinueWithApple,
                        ),
                        const SizedBox(height: 14),
                        SecondaryAuthButton(
                          label: 'Continue with Google',
                          onPressed: onContinueWithGoogle,
                        ),
                        const SizedBox(height: 6),
                        UnderlinedTextButton(
                          label: 'Use email or phone',
                          onPressed:
                              onUseEmailOrPhone ??
                              () => EmailAuthSheet.show(context),
                        ),
                        const SizedBox(height: 14),
                        Glyph('❤️', size: context.glyphs.heart),
                        const SizedBox(height: 6),
                        Text(
                          'No audience. Just us.',
                          style: theme.textTheme.titleMedium!.copyWith(
                            color: context.palette.inkFaint,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Small sage capsule above the bouquet.
class _PrivateSpaceBadge extends StatelessWidget {
  const _PrivateSpaceBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: ShapeDecoration(
        color: theme.colorScheme.secondaryContainer,
        shape: const StadiumBorder(),
      ),
      child: Text(
        'PRIVATE SPACE',
        style: theme.textTheme.labelSmall!.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

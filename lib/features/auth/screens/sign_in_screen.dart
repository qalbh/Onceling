import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/app_toast.dart';
import '../../../common/providers.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../../../theme/theme_glyphs.dart';
import '../widgets/auth_buttons.dart';
import '../widgets/email_auth_sheet.dart';
import '../auth_service.dart';
import '../widgets/floral_hero.dart';

/// Entry screen: brand mark over the bouquet, sign-in options pinned low.
///
/// **Two options, styled identically.** Google and email both work, and neither
/// is presented as the better one — see [AuthButton].
///
/// Apple was here as a permanently disabled button until there is a paid Apple
/// Developer account (**P2-20**). That was the wrong call: on the first screen a
/// user ever sees, a dead control does not read as "coming soon", it reads as
/// broken software. It is gone from the UI entirely, which changes nothing about
/// the obligation — Guideline 4.8 still makes Sign in with Apple mandatory for
/// the iOS build the moment Google sign-in ships there.
///
/// Nothing here navigates on success: auth-gated routing is **P2-14**.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({
    super.key,
    this.onContinueWithGoogle,
    this.onUseEmailOrPhone,
  });

  /// Overrides the built-in Google handler. Tests pass one; the app does not.
  final VoidCallback? onContinueWithGoogle;

  /// Defaults to opening [EmailAuthSheet].
  final VoidCallback? onUseEmailOrPhone;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;

  /// **P2-19.** No navigation on success — the gate sees the auth change and
  /// moves the whole app, exactly as the email path does. Navigating here too
  /// would race it.
  Future<void> _google() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } on AuthFailure catch (failure) {
      if (mounted) showAppToast(context, failure.message);
    } catch (_) {
      if (mounted) {
        showAppToast(context, 'Something went wrong. Try again.');
      }
    } finally {
      // The widget is gone on success — the gate has already routed away.
      if (mounted) setState(() => _busy = false);
    }
  }

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
                        AuthButton(
                          label: 'Continue with Google',
                          onPressed: _busy
                              ? null
                              : (widget.onContinueWithGoogle ?? _google),
                        ),
                        const SizedBox(height: 14),
                        AuthButton(
                          label: 'Sign in with email',
                          onPressed:
                              widget.onUseEmailOrPhone ??
                              () => EmailAuthSheet.show(context),
                        ),
                        const SizedBox(height: 20),
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

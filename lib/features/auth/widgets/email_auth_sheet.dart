import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/providers.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../auth_service.dart';

/// Email and password, sign-in and sign-up in one sheet.
///
/// **This sheet does not dismiss itself on success, and must not.** Signing in
/// changes auth state, the gate (**P2-14**) re-runs, and go_router replaces the
/// whole page stack — `/` becomes `/splash` and then `/pairing` or `/feed`.
/// This sheet is a *pageless* route attached to the `/` page, so that
/// replacement disposes it. Dismissal is something that happens to it, not
/// something it does.
///
/// Popping here is a race, not a tidy-up: by the time an `await`ed sign-in
/// returns, the page this sheet was attached to may already be gone, and
/// popping into a Navigator mid-rebuild is what produced the duplicate-GlobalKey
/// crash on first sign-in. Device traces showed two page-stack replacements
/// landing inside that await, with `mounted` already false at pop time — the
/// pop was dead code on the success path even before it was removed.
///
/// The failure path is different: nothing navigates, the sheet stays open, and
/// it shows its own error.
class EmailAuthSheet extends ConsumerStatefulWidget {
  const EmailAuthSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (_) => const EmailAuthSheet(),
    );
  }

  @override
  ConsumerState<EmailAuthSheet> createState() => _EmailAuthSheetState();
}

class _EmailAuthSheetState extends ConsumerState<EmailAuthSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();

  bool _isSignUp = false;
  bool _busy = false;
  String? _error;

  /// Empty state: nothing to submit until both required fields have something.
  bool get _canSubmit =>
      !_busy && _email.text.trim().isNotEmpty && _password.text.isNotEmpty;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Guards the double tap as well as the disabled state.
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final service = ref.read(authServiceProvider);
    try {
      if (_isSignUp) {
        await service.signUp(
          email: _email.text,
          password: _password.text,
          displayName: _displayName.text,
        );
      } else {
        await service.signIn(email: _email.text, password: _password.text);
      }
      // No pop. The gate is already replacing the page stack underneath this
      // sheet, which disposes it — see the class comment. Success leaves this
      // method having done exactly one thing: called the service.
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _error = null;
    });
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
                const _DragHandle(),
                const SizedBox(height: 22),
                Text(
                  _isSignUp ? 'Make an account' : 'Welcome back',
                  style: AppTheme.wordmark(context, 28),
                ),
                const SizedBox(height: 20),
                if (_isSignUp) ...[
                  _Field(
                    controller: _displayName,
                    hint: 'Your name',
                    enabled: !_busy,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                ],
                _Field(
                  controller: _email,
                  hint: 'Email',
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _Field(
                  controller: _password,
                  hint: 'Password',
                  enabled: !_busy,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error case final message?) ...[
                  const SizedBox(height: 14),
                  _ErrorText(message: message),
                ],
                const SizedBox(height: 22),
                _SubmitButton(
                  label: _isSignUp ? 'Create account' : 'Sign in',
                  busy: _busy,
                  onPressed: _canSubmit ? _submit : null,
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : _toggleMode,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                    ),
                    child: Text(
                      _isSignUp
                          ? 'I already have an account'
                          : 'Create an account instead',
                    ),
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

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.enabled,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: theme.textTheme.headlineLarge,
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: hint,
          hintStyle: theme.textTheme.headlineLarge!.copyWith(
            color: context.palette.inkFaint,
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Icon(Icons.error_outline, size: 19, color: context.palette.dangerInk),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.titleLarge!.copyWith(
              height: 1.35,
              color: context.palette.dangerInk,
            ),
          ),
        ),
      ],
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          disabledBackgroundColor: context.palette.sageDisabled,
          disabledForegroundColor: theme.colorScheme.onPrimary,
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: AppTheme.bold(theme.textTheme.headlineLarge!),
        ),
        child: busy
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(
                    theme.colorScheme.onPrimary,
                  ),
                ),
              )
            : Text(label),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 46,
        height: 5,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outline,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
